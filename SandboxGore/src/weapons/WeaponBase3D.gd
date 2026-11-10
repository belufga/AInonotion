class_name WeaponBase3D
extends Node3D
## Unified base for everything the player holds: firearms, the grenade and the toolgun.
##
## Provides the procedural viewmodel (hip and aim-down-sights poses, a second-order recoil
## spring, look sway, walk bob, reload dip), magazine and fire-mode logic, and camera recoil and
## shake requests. The shot itself belongs to a BallisticsComponent, which firearms supply
## through `_make_ballistics`. Subclasses configure the exported values in `_init` and override
## the underscore hooks.

enum FireMode { SEMI, AUTO, PUMP }

signal fired
signal ammo_changed

@export var display_name := "Weapon"
@export var weapon_id: StringName = &"ak47"  ## Model, pickup and ammunition identity.
@export var fire_mode := FireMode.SEMI
@export var rpm := 600.0
@export var uses_ammo := true
@export var magazine_size := 30
@export var reserve_ammo := 120
@export var reload_time := 2.4
@export var reload_per_round := false      ## Tube magazines load one shell per reload cycle.
@export_group("Accuracy")
@export var hip_spread := 1.2              ## Cone half-angle in degrees.
@export var ads_spread := 0.25
@export var move_spread := 1.5             ## Added at full running speed.
@export var bloom_per_shot := 0.35
@export var bloom_decay := 4.0             ## Degrees per second.
@export_group("Recoil")
@export var recoil_pitch := 1.2            ## Camera kick in degrees per shot.
@export var recoil_yaw := 0.5
@export var recoil_climb := 0.5            ## Share of the kick the camera keeps (muzzle climb).
@export var kick_back := 0.035             ## Viewmodel recoil travel in metres.
@export var kick_up := 4.0                 ## Viewmodel muzzle rise in degrees.
@export var spring_stiffness := 190.0
@export var spring_damping := 18.0
@export var shake := 0.15
@export_group("View")
@export var can_aim := true
@export var ads_fov := 60.0
@export var hip_offset := Vector3(0.16, -0.14, -0.38)
@export var ads_offset := Vector3(0.0, -0.062, -0.3)
@export var sway := 0.004                  ## Metres of lag per rad/s of look speed.
@export var sound: StringName = &"rifle"

var ballistics: BallisticsComponent  ## Projectile emitter; null for items that do not shoot.
var wielder: Node  ## Needs get_aim_transform(); apply_recoil(), add_shake() and velocity are optional.
var ammo := 0
var is_reloading := false
var is_aiming := false
var model: Node3D
var muzzle: Marker3D

var _trigger_held := false
var _cooldown := 0.0
var _reload_left := 0.0
var _bloom := 0.0
var _ads := 0.0
var _equip := 0.0
var _kick_position := Vector3.ZERO
var _kick_position_velocity := Vector3.ZERO
var _kick_rotation := Vector3.ZERO
var _kick_rotation_velocity := Vector3.ZERO
var _sway := Vector2.ZERO
var _bob_time := 0.0
var _flash: Node3D
var _flash_left := 0.0


func _ready() -> void:
	ballistics = _make_ballistics()
	if ballistics != null:
		add_child(ballistics)
	model = _build_model()
	add_child(model)
	muzzle = model.get_node_or_null(^"Muzzle") as Marker3D
	ammo = magazine_size
	if uses_ammo and muzzle != null:
		_build_flash()
	visible = false
	_setup()


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_bloom = maxf(_bloom - bloom_decay * delta, 0.0)
	if is_reloading:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()
	elif _trigger_held and fire_mode == FireMode.AUTO:
		_try_fire()


# --- interface used by the wielder --------------------------------------------------------

func equip(p_wielder: Node) -> void:
	wielder = p_wielder
	visible = true
	_equip = 0.0


func unequip() -> void:
	visible = false
	_trigger_held = false
	is_reloading = false
	is_aiming = false


func trigger_pressed() -> void:
	_trigger_held = true
	if is_reloading and reload_per_round and ammo > 0:
		is_reloading = false  # A tube reload can be interrupted to fire what is loaded.
	_try_fire()


func trigger_released() -> void:
	_trigger_held = false


func secondary_pressed() -> void:
	is_aiming = can_aim


func secondary_released() -> void:
	is_aiming = false


func reload() -> void:
	if not uses_ammo or is_reloading or ammo >= magazine_size or reserve_ammo == 0:
		return
	is_reloading = true
	_reload_left = reload_time


## Mouse wheel while this item is held. Return true to consume it instead of switching weapons.
func scroll(_direction: int) -> bool:
	return false


func add_reserve(rounds: int) -> void:
	reserve_ammo += rounds
	ammo_changed.emit()


func ads_amount() -> float:
	return _ads


func current_spread() -> float:
	var speed := 0.0
	if wielder != null and "velocity" in wielder:
		speed = (wielder.get("velocity") as Vector3).length()
	return lerpf(hip_spread, ads_spread, _ads) + _bloom + move_spread * clampf(speed / 7.5, 0.0, 1.0)


func ammo_text() -> String:
	if not uses_ammo:
		return ""
	return "%d / %d%s" % [ammo, reserve_ammo, "  RELOADING" if is_reloading else ""]


func hud_hint() -> String:
	return "LMB fire   RMB aim   R reload"


## Where the muzzle appears on screen. The viewmodel renders with its own field of view, so the
## node's real position has to be rescaled into the camera's projection for tracers to line up.
func get_muzzle_position() -> Vector3:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null or muzzle == null:
		return global_position
	var local := camera.global_transform.affine_inverse() * muzzle.global_position
	var k := tan(deg_to_rad(camera.fov) * 0.5) / tan(deg_to_rad(WeaponModels.VIEWMODEL_FOV) * 0.5)
	return camera.global_transform * Vector3(local.x * k, local.y * k, local.z)


## Called every rendered frame by the wielder to pose the viewmodel.
## `look_rate` is the camera's turn rate in rad/s (x yaw, y pitch).
func update_view(delta: float, look_rate: Vector2, speed: float, grounded: bool) -> void:
	delta = minf(delta, 1.0 / 30.0)
	_equip = move_toward(_equip, 1.0, delta * 5.0)
	_ads = move_toward(_ads, 1.0 if (is_aiming and can_aim and not is_reloading) else 0.0, delta * 7.0)

	# Recoil: a damped spring pulls the kick back to rest.
	_kick_position_velocity += (-spring_stiffness * _kick_position - spring_damping * _kick_position_velocity) * delta
	_kick_position += _kick_position_velocity * delta
	_kick_rotation_velocity += (-spring_stiffness * _kick_rotation - spring_damping * _kick_rotation_velocity) * delta
	_kick_rotation += _kick_rotation_velocity * delta

	var hip := 1.0 - 0.8 * _ads
	var lag := (Vector2(-look_rate.x, look_rate.y) * sway).limit_length(0.035)
	_sway = _sway.lerp(lag, 1.0 - exp(-12.0 * delta))
	if grounded and speed > 0.5:
		_bob_time += delta * (4.0 + speed * 1.2)
	var bob := Vector3(cos(_bob_time) * 0.004, -absf(sin(_bob_time)) * 0.005, 0.0) * clampf(speed / 4.5, 0.0, 1.5) * hip
	var lowered := 1.0 - _equip
	var dip := 0.0
	if is_reloading:
		dip = sin(clampf(1.0 - _reload_left / reload_time, 0.0, 1.0) * PI)
	model.position = hip_offset.lerp(ads_offset, _ads) + _kick_position + bob \
		+ Vector3(_sway.x * hip, _sway.y * hip - 0.22 * lowered - 0.1 * dip, 0.0)
	model.rotation = _kick_rotation + Vector3(-0.7 * lowered - 0.45 * dip + _sway.y * 2.0 * hip, _sway.x * 3.0 * hip, -_sway.x * 2.0 * hip)

	if _flash != null and _flash.visible:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_flash.visible = false
	_animate(delta)


# --- hooks for subclasses -----------------------------------------------------------------

## Firearms return their projectile emitter here; items that do not shoot return null.
func _make_ballistics() -> BallisticsComponent:
	return null


func _build_model() -> Node3D:
	return WeaponModels.build(weapon_id, true)


## Called once after the model exists; grab animated parts here.
func _setup() -> void:
	pass


## Per-frame action animation (slide, pump, bolt).
func _animate(_delta: float) -> void:
	pass


func _on_fired() -> void:
	pass


# --- firing -------------------------------------------------------------------------------

func _try_fire() -> bool:
	if _cooldown > 0.0 or is_reloading or wielder == null:
		return false
	if uses_ammo and ammo <= 0:
		Sfx.play(&"click", global_position, -6.0)
		_cooldown = 0.25
		reload()
		return false
	_fire()
	return true


func _fire() -> void:
	if uses_ammo:
		ammo -= 1
	_cooldown = 60.0 / rpm
	var aim: Transform3D = wielder.get_aim_transform()
	_shoot(aim)
	_bloom = minf(_bloom + bloom_per_shot, 4.0)

	_kick_position_velocity.z += kick_back * 28.0
	_kick_rotation_velocity += Vector3(1.0, randf_range(-0.2, 0.2), randf_range(-0.3, 0.3)) * deg_to_rad(kick_up) * 28.0
	var steadied := lerpf(1.0, 0.65, _ads)
	if wielder.has_method(&"apply_recoil"):
		wielder.apply_recoil(recoil_pitch * steadied, recoil_yaw * randf_range(-1.0, 1.0) * steadied, recoil_climb)
	if wielder.has_method(&"add_shake"):
		wielder.add_shake(shake)
	if _flash != null:
		_flash.visible = true
		_flash.rotation.z = randf() * TAU
		_flash_left = 0.045
	Sfx.play(sound, aim.origin)
	get_tree().call_group(Humanoid.GROUP, &"hear_noise", aim.origin)
	_on_fired()
	fired.emit()
	ammo_changed.emit()


## Fired from the eye along the aim axis so hits match the crosshair; tracers start at the muzzle.
func _shoot(aim: Transform3D) -> void:
	ballistics.fire(aim, current_spread(), wielder, get_muzzle_position())


func _finish_reload() -> void:
	if reload_per_round:
		ammo += 1
		reserve_ammo -= 1
		Sfx.play(&"click", global_position, -4.0)
		if ammo < magazine_size and reserve_ammo > 0:
			_reload_left = reload_time
		else:
			is_reloading = false
	else:
		var loaded := mini(magazine_size - ammo, reserve_ammo)
		ammo += loaded
		reserve_ammo -= loaded
		is_reloading = false
	ammo_changed.emit()


func _build_flash() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(1.0, 0.75, 0.3, 0.9)
	material.use_fov_override = true
	material.fov_override = WeaponModels.VIEWMODEL_FOV
	material.use_z_clip_scale = true
	material.z_clip_scale = 0.35
	_flash = Node3D.new()
	_flash.visible = false
	muzzle.add_child(_flash)
	# Two crossed quads read as a star from the shooter's eye.
	for angle: float in [0.0, PI / 2.0]:
		var quad := QuadMesh.new()
		quad.size = Vector2(0.16, 0.05)
		var blade := MeshInstance3D.new()
		blade.mesh = quad
		blade.material_override = material
		blade.rotation.z = angle
		blade.layers = Layers.VIS_VIEWMODEL
		blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_flash.add_child(blade)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.4)
	light.light_energy = 2.5
	light.omni_range = 7.0
	_flash.add_child(light)
