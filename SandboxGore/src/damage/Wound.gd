class_name Wound
extends RefCounted
## A bleeding site anchored to a bone. VitalsComponent drains blood through it; GoreComponent
## turns the lost volume into spurts, drips and pools.

var bone: Node3D
var local_position := Vector3.ZERO
var local_normal := Vector3.UP
var rate := 0.0            ## ml/s at normal arterial pressure.
var flow := 0.0            ## ml/s leaving right now, after pressure scaling.
var arterial := false      ## Pressure-driven and pulsatile; never clots on its own.
var clot_halflife := 35.0  ## Seconds; 0 disables clotting.
var label := &"wound"
var lost := 0.0            ## Total ml lost through this wound.
var pending := 0.0         ## ml not yet turned into drips or pools.


static func create(p_bone: Node3D, world_position: Vector3, world_normal: Vector3, p_rate: float,
		p_arterial := false, p_clot := 35.0, p_label := &"wound") -> Wound:
	var w := Wound.new()
	w.bone = p_bone
	var inverse := p_bone.global_transform.affine_inverse()
	w.local_position = inverse * world_position
	w.local_normal = (inverse.basis * world_normal).normalized()
	w.rate = p_rate
	w.arterial = p_arterial
	w.clot_halflife = p_clot
	w.label = p_label
	return w


func is_valid() -> bool:
	return is_instance_valid(bone) and bone.is_inside_tree()


func world_position() -> Vector3:
	return bone.global_transform * local_position


func world_normal() -> Vector3:
	return (bone.global_basis * local_normal).normalized()
