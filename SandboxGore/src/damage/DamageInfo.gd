class_name DamageInfo
extends RefCounted
## One damage event, shared by every damage source and receiver.

enum Type { BALLISTIC, SHRAPNEL, BLUNT, BLAST }

var type := Type.BALLISTIC
var amount := 0.0        ## Generic hit points. When zero, HealthComponent derives it from the fields below.
var energy := 0.0        ## Joules deposited in the target.
var overpressure := 0.0  ## kPa, blast only.
var impulse := Vector3.ZERO
var position := Vector3.ZERO
var direction := Vector3.FORWARD
var normal := Vector3.UP
var exit_position := Vector3.ZERO
var exited := false
var tumbling := false
var bone_hit := false
var part: StringName
var organs: Array[StringName] = []
var caliber: Caliber
var attacker: Node


static func make(p_type: Type, p_position: Vector3, p_direction: Vector3, p_attacker: Node = null) -> DamageInfo:
	var info := DamageInfo.new()
	info.type = p_type
	info.position = p_position
	info.direction = p_direction
	info.attacker = p_attacker
	return info
