class_name Pistol
extends WeaponBase3D
## Semi-automatic tactical pistol, 9x19mm Parabellum. Precise and low on penetration: built for
## placed shots at specific organs rather than for punching through cover.

const SLIDE_TRAVEL := 0.035

var _slide: Node3D
var _slide_rest := 0.0
var _slide_offset := 0.0


func _init() -> void:
	display_name = "Tactical Pistol 9x19mm"
	weapon_id = &"pistol"
	fire_mode = FireMode.SEMI
	rpm = 420.0
	magazine_size = 17
	reserve_ammo = 102
	reload_time = 1.6
	hip_spread = 0.9
	ads_spread = 0.12
	bloom_per_shot = 0.25
	recoil_pitch = 1.4
	recoil_yaw = 0.5
	recoil_climb = 0.35
	kick_back = 0.028
	kick_up = 6.0
	shake = 0.1
	ads_fov = 65.0
	hip_offset = Vector3(0.14, -0.13, -0.34)
	ads_offset = Vector3(0.0, -0.053, -0.28)
	sound = &"pistol"


func _make_ballistics() -> BallisticsComponent:
	return BallisticsComponent.create(Caliber.parabellum_9mm(), 40.0)


func _setup() -> void:
	_slide = model.get_node(^"Slide")
	_slide_rest = _slide.position.z


func _on_fired() -> void:
	_slide_offset = SLIDE_TRAVEL  # Blowback: the slide snaps to the rear with the shot.


func _animate(delta: float) -> void:
	# The slide runs forward again unless the magazine is empty, when it locks open.
	var target := SLIDE_TRAVEL if ammo == 0 and not is_reloading else 0.0
	_slide_offset = move_toward(_slide_offset, target, delta * 0.7)
	_slide.position.z = _slide_rest + _slide_offset
