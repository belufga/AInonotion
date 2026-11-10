class_name BallisticShot
extends RefCounted
## State of one projectile in flight. Speed is the primary quantity; energy is derived from it.

var caliber: Caliber
var position := Vector3.ZERO
var direction := Vector3.FORWARD
var speed := 0.0
var attacker: Node
var damage_type := DamageInfo.Type.BALLISTIC
var flesh_depth := 0.0   ## Metres of tissue crossed so far; decides when the bullet yaws.
var tumbling := false
var distance := 0.0
var age := 0.0
var alive := true
var record := false      ## Keep a per-surface log in `hits` (tests, telemetry).
var hits: Array[Dictionary] = []

var energy: float:
	get:
		return 0.5 * caliber.mass * speed * speed
	set(value):
		speed = sqrt(maxf(value, 0.0) * 2.0 / caliber.mass)

var velocity: Vector3:
	get:
		return direction * speed
	set(value):
		speed = value.length()
		if speed > 0.0:
			direction = value / speed


## The attacker may have been deleted while this shot was still in flight.
func live_attacker() -> Node:
	return attacker if is_instance_valid(attacker) else null


static func create(p_caliber: Caliber, origin: Vector3, p_direction: Vector3, p_attacker: Node = null,
		p_speed := -1.0, p_type := DamageInfo.Type.BALLISTIC) -> BallisticShot:
	var shot := BallisticShot.new()
	shot.caliber = p_caliber
	shot.position = origin
	shot.direction = p_direction.normalized()
	shot.speed = p_caliber.muzzle_velocity if p_speed < 0.0 else p_speed
	shot.attacker = p_attacker
	shot.damage_type = p_type
	return shot
