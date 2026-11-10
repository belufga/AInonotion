class_name AK47
extends WeaponBase3D
## AK-47 assault rifle, 7.62x39mm. Full-automatic at about 600 rounds per minute with a heavy,
## climbing recoil. The round carries four times a pistol bullet's energy: it goes through
## wooden cover, thin steel, limbs and torsos, yaws inside tissue and leaves large exit wounds.

const BOLT_TRAVEL := 0.03

var _bolt: Node3D
var _bolt_rest := 0.0
var _bolt_offset := 0.0


func _init() -> void:
	display_name = "AK-47 7.62x39mm"
	weapon_id = &"ak47"
	fire_mode = FireMode.AUTO
	rpm = 600.0
	magazine_size = 30
	reserve_ammo = 180
	reload_time = 2.5
	hip_spread = 1.6
	ads_spread = 0.3
	move_spread = 2.0
	bloom_per_shot = 0.5
	recoil_pitch = 1.9
	recoil_yaw = 1.1
	recoil_climb = 0.6
	kick_back = 0.045
	kick_up = 5.0
	shake = 0.22
	ads_fov = 55.0
	hip_offset = Vector3(0.16, -0.15, -0.3)
	ads_offset = Vector3(0.0, -0.062, -0.22)
	sound = &"rifle"


func _make_ballistics() -> BallisticsComponent:
	return BallisticsComponent.create(Caliber.soviet_762x39(), 60.0)


func _setup() -> void:
	_bolt = model.get_node(^"Bolt")
	_bolt_rest = _bolt.position.z


func _on_fired() -> void:
	_bolt_offset = BOLT_TRAVEL


func _animate(delta: float) -> void:
	_bolt_offset = move_toward(_bolt_offset, 0.0, delta * 0.9)
	_bolt.position.z = _bolt_rest + _bolt_offset
