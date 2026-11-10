class_name Player
extends CharacterBody3D
## First-person controller: movement, mouse look, the weapon inventory, camera recoil and shake,
## and the input routing for weapons, the toolgun and the radial wheels.

const GROUP := &"player"
const EYE_HEIGHT := 1.62
const MAX_PITCH := 1.5

@export var walk_speed := 4.5
@export var sprint_speed := 7.5
@export var jump_speed := 5.2
@export var mouse_sensitivity := 0.0022
@export var base_fov := 80.0

var camera: Camera3D
var hand: Node3D
var hud: HUD
var weapons: Array[WeaponBase3D] = []
var toolgun: Toolgun
var noclip := false

var _current := -1
var _yaw := 0.0
var _pitch := 0.0
var _recoil := Vector2.ZERO          ## Transient camera kick (pitch, yaw) that springs back.
var _recoil_velocity := Vector2.ZERO
var _trauma := 0.0
var _look := Vector2.ZERO            ## Look rotation accumulated since the last rendered frame.
var _hud_timer := 0.0
var _menu: StringName = &""


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = Layers.PLAYER
	collision_mask = Layers.WORLD | Layers.PROPS
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	var collider := CollisionShape3D.new()
	collider.shape = capsule
	collider.position.y = 0.9
	add_child(collider)

	camera = Camera3D.new()
	camera.position.y = EYE_HEIGHT
	camera.fov = base_fov
	camera.near = 0.03
	camera.far = 600.0
	add_child(camera)
	camera.make_current()
	hand = Node3D.new()
	hand.name = "Hand"
	camera.add_child(hand)

	hud = HUD.new()
	add_child(hud)

	toolgun = Toolgun.new()
	for weapon: WeaponBase3D in [toolgun, Pistol.new(), Shotgun.new(), AK47.new(), FragGrenade.new()]:
		hand.add_child(weapon)
		weapons.append(weapon)
	_yaw = rotation.y
	equip(0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func current_weapon() -> WeaponBase3D:
	return weapons[_current]


func equip(index: int) -> void:
	index = posmod(index, weapons.size())
	if index == _current:
		return
	if _current >= 0:
		weapons[_current].unequip()
	_current = index
	weapons[_current].equip(self)


## The eye: weapons shoot from here along -Z so hits match the crosshair.
func get_aim_transform() -> Transform3D:
	return camera.global_transform


## `climb` is the share of the kick the view keeps; the rest springs back.
func apply_recoil(pitch_degrees: float, yaw_degrees: float, climb: float) -> void:
	var pitch := deg_to_rad(pitch_degrees)
	var yaw := deg_to_rad(yaw_degrees)
	_pitch = clampf(_pitch + pitch * climb, -MAX_PITCH, MAX_PITCH)
	_yaw += yaw * climb
	_recoil_velocity += Vector2(pitch, yaw) * (1.0 - climb) * 26.0


func add_shake(amount: float) -> void:
	_trauma = minf(_trauma + amount, 1.0)


## Group callback from Explosion.
func on_explosion(origin: Vector3, size: float) -> void:
	add_shake(clampf(size * 7.0 / maxf(global_position.distance_to(origin), 1.0), 0.0, 1.0))


func look_at_point(target: Vector3) -> void:
	var offset := target - (global_position + Vector3.UP * EYE_HEIGHT)
	_yaw = atan2(-offset.x, -offset.z)
	_pitch = clampf(atan2(offset.y, Vector2(offset.x, offset.z).length()), -MAX_PITCH, MAX_PITCH)
	_apply_view(0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
		var relative: Vector2 = event.relative
		if hud.radial.is_open:
			hud.radial.feed(relative)
		elif toolgun.rotating and toolgun.is_holding():
			toolgun.rotate_input(relative)
		else:
			var scale := mouse_sensitivity * lerpf(1.0, 0.55, current_weapon().ads_amount())
			_yaw -= relative.x * scale
			_pitch = clampf(_pitch - relative.y * scale, -MAX_PITCH, MAX_PITCH)
			_look += relative * scale
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	var weapon := current_weapon()
	if event.is_action_pressed(&"fire"):
		if not hud.radial.is_open:
			weapon.trigger_pressed()
	elif event.is_action_released(&"fire"):
		weapon.trigger_released()
	elif event.is_action_pressed(&"aim"):
		weapon.secondary_pressed()
	elif event.is_action_released(&"aim"):
		weapon.secondary_released()
	elif event.is_action_pressed(&"reload"):
		weapon.reload()
	elif event.is_action_pressed(&"interact"):
		_interact()
	elif event.is_action_pressed(&"weapon_prev"):
		if not weapon.scroll(1):
			equip(_current - 1)
	elif event.is_action_pressed(&"weapon_next"):
		if not weapon.scroll(-1):
			equip(_current + 1)
	elif event.is_action_pressed(&"tool_menu"):
		_open_menu(&"tool")
	elif event.is_action_pressed(&"spawn_menu"):
		_open_menu(&"spawn")
	elif event.is_action_released(&"tool_menu") or event.is_action_released(&"spawn_menu"):
		_close_menu()
	elif event.is_action_pressed(&"tool_rotate"):
		toolgun.rotating = true
	elif event.is_action_released(&"tool_rotate"):
		toolgun.rotating = false
	elif event.is_action_pressed(&"slow_motion"):
		Engine.time_scale = 0.2 if Engine.time_scale > 0.5 else 1.0
	elif event.is_action_pressed(&"noclip"):
		noclip = not noclip
	elif event.is_action_pressed(&"toggle_help"):
		hud.toggle_help()
	elif event.is_action_pressed(&"clear_gore"):
		clear_gore()
	elif event.is_action_pressed(&"restart_scene"):
		Engine.time_scale = 1.0
		BloodFX.clear()
		Ballistics.clear()
		get_tree().reload_current_scene()
	else:
		for i in weapons.size():
			if event.is_action_pressed("weapon_%d" % (i + 1)):
				equip(i)


func _physics_process(delta: float) -> void:
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var speed := sprint_speed if Input.is_action_pressed(&"sprint") else walk_speed
	if noclip:
		var fly := camera.global_basis * Vector3(input.x, 0.0, input.y)
		velocity = fly * speed * 2.0
		global_position += velocity * delta
		return
	var wish := Basis(Vector3.UP, _yaw) * Vector3(input.x, 0.0, input.y) * speed
	if is_on_floor():
		velocity.x = move_toward(velocity.x, wish.x, 60.0 * delta)
		velocity.z = move_toward(velocity.z, wish.z, 60.0 * delta)
		if Input.is_action_just_pressed(&"jump"):
			velocity.y = jump_speed
	else:
		velocity.x = move_toward(velocity.x, wish.x, 12.0 * delta)
		velocity.z = move_toward(velocity.z, wish.z, 12.0 * delta)
		velocity.y -= 15.0 * delta
	move_and_slide()
	# A kinematic character does not push dynamic bodies by itself.
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var body := collision.get_collider() as RigidBody3D
		if body != null and not body.freeze:
			body.apply_impulse(-collision.get_normal() * minf(body.mass, 40.0) * 0.3, collision.get_position() - body.global_position)


func _process(delta: float) -> void:
	_apply_view(delta)
	var weapon := current_weapon()
	camera.fov = lerpf(base_fov, weapon.ads_fov, weapon.ads_amount())
	weapon.update_view(delta, _look / maxf(delta, 0.0001), Vector3(velocity.x, 0.0, velocity.z).length(), is_on_floor())
	_look = Vector2.ZERO
	# Crosshair arms sit on the edge of the current spread cone.
	var half_height := get_viewport().get_visible_rect().size.y * 0.5
	hud.set_crosshair_gap(4.0 + tan(deg_to_rad(weapon.current_spread())) * half_height / tan(deg_to_rad(camera.fov) * 0.5))
	hud.set_weapon(weapon.display_name, weapon.ammo_text(), weapon.hud_hint())
	_hud_timer -= delta
	if _hud_timer <= 0.0:
		_hud_timer = 0.1
		_refresh_hud()


## Removes the dead and everything they left behind.
func clear_gore() -> void:
	BloodFX.clear()
	for npc: Humanoid in get_tree().get_nodes_in_group(Humanoid.GROUP):
		if not npc.is_alive():
			npc.queue_free()


func _apply_view(delta: float) -> void:
	var step := minf(delta, 1.0 / 30.0)
	_recoil_velocity += (-170.0 * _recoil - 20.0 * _recoil_velocity) * step
	_recoil += _recoil_velocity * step
	_trauma = maxf(_trauma - 1.6 * delta, 0.0)
	var shake := _trauma * _trauma * 0.035
	var time := Time.get_ticks_msec() * 0.001
	rotation.y = _yaw + _recoil.y + sin(time * 53.0 + 1.3) * shake
	camera.rotation = Vector3(clampf(_pitch + _recoil.x, -MAX_PITCH, MAX_PITCH) + sin(time * 47.0) * shake, 0.0, sin(time * 41.0 + 2.1) * shake)


func _open_menu(kind: StringName) -> void:
	if hud.radial.is_open:
		return
	equip(0)
	_menu = kind
	if kind == &"tool":
		hud.radial.open("TOOL", Toolgun.MODES, toolgun.mode)
	else:
		hud.radial.open("SPAWN", SpawnCatalog.ITEMS, SpawnCatalog.ITEMS.find(SpawnCatalog.find(toolgun.spawn_id)))


func _close_menu() -> void:
	if not hud.radial.is_open:
		return
	var index := hud.radial.close()
	if index < 0:
		return
	if _menu == &"tool":
		toolgun.set_mode(index as Toolgun.Mode)
	else:
		toolgun.spawn_id = SpawnCatalog.ITEMS[index].id
		toolgun.set_mode(Toolgun.Mode.SPAWN)


## Picks up a weapon prop in reach and turns it into reserve ammunition.
func _interact() -> void:
	var aim := get_aim_transform()
	var query := PhysicsRayQueryParameters3D.create(aim.origin, aim.origin - aim.basis.z * 3.5, Layers.PROPS)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var pickup := hit.get("collider") as WeaponPickup
	if pickup == null:
		return
	for weapon in weapons:
		if weapon.weapon_id == pickup.weapon_id:
			weapon.add_reserve(weapon.magazine_size * 2)
			Sfx.play(&"click", pickup.global_position)
			pickup.queue_free()
			return


func _refresh_hud() -> void:
	var aim := get_aim_transform()
	var query := PhysicsRayQueryParameters3D.create(aim.origin, aim.origin - aim.basis.z * 80.0, Layers.BALLISTIC)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var text := ""
	if not hit.is_empty():
		var collider: Object = hit.collider
		var humanoid := Layers.entity_root(collider as Node) as Humanoid
		var health := HealthComponent.of(collider)
		if humanoid != null:
			var hitbox := HitboxComponent.of(collider)
			text = humanoid.inspect_text()
			if hitbox != null:
				text += "\nAiming at: " + String(hitbox.part)
		elif health != null:
			text = "%s\nIntegrity %d / %d" % [(collider as Node).name, roundi(health.health), roundi(health.max_health)]
	hud.set_inspect(text)
	var stats: Dictionary = BloodFX.stats()
	hud.set_stats("%d FPS\nDecals %d / %d   Gibs %d\nProjectiles %d   Time x%.1f%s" % [
		Engine.get_frames_per_second(), stats.decals, stats.decal_capacity, stats.gibs,
		Ballistics.flying_count(), Engine.time_scale, "   NOCLIP" if noclip else ""])
