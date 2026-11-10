class_name Shotgun
extends WeaponBase3D
## Pump-action shotgun, 12 gauge 00 buckshot.
##
## Each shell throws `pellet_count` pellets in a cone, each traced as its own projectile. At
## point-blank range the whole pattern lands on one body part inside a single frame, which is
## exactly what the dismemberment model accumulates: limbs come off and torsos are knocked flat.

const PUMP_TRAVEL := 0.09

@export_range(8, 12) var pellet_count := 9
@export var pump_time := 0.55  ## Seconds to cycle the action; no shot until it is done.

var _pump: Node3D
var _pump_rest := 0.0
var _pump_left := 0.0
var _pump_clicked := true


func _init() -> void:
	display_name = "Pump Shotgun 12ga 00 Buck"
	weapon_id = &"shotgun"
	fire_mode = FireMode.PUMP
	magazine_size = 6
	reserve_ammo = 48
	reload_time = 0.45
	reload_per_round = true
	hip_spread = 3.0
	ads_spread = 2.3
	move_spread = 0.8
	bloom_per_shot = 0.0
	recoil_pitch = 5.5
	recoil_yaw = 1.6
	recoil_climb = 0.4
	kick_back = 0.08
	kick_up = 12.0
	shake = 0.45
	ads_fov = 68.0
	hip_offset = Vector3(0.15, -0.15, -0.36)
	ads_offset = Vector3(0.0, -0.045, -0.3)
	sound = &"shotgun"


func _ready() -> void:
	rpm = 60.0 / pump_time
	super()


func _make_ballistics() -> BallisticsComponent:
	return BallisticsComponent.create(Caliber.buckshot_00(), 35.0, pellet_count)


func _setup() -> void:
	_pump = model.get_node(^"Pump")
	_pump_rest = _pump.position.z


func _on_fired() -> void:
	_pump_left = pump_time
	_pump_clicked = false


func _animate(delta: float) -> void:
	if _pump_left <= 0.0:
		return
	_pump_left = maxf(_pump_left - delta, 0.0)
	# Fore-end back to eject, forward to chamber; starts a beat after the shot.
	var progress := clampf((1.0 - _pump_left / pump_time - 0.25) / 0.75, 0.0, 1.0)
	_pump.position.z = _pump_rest + sin(progress * PI) * PUMP_TRAVEL
	if progress > 0.5 and not _pump_clicked:
		_pump_clicked = true
		Sfx.play(&"pump", global_position, -3.0)
