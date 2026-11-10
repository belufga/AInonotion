class_name ActiveRagdoll
extends Node
## Hybrid active ragdoll controller.
##
## Every physics tick the animated pose on the AnimRig skeleton is compared with the simulated
## bones, and each joint is driven toward it by an angular spring-damper (PD) motor.
##
## The motors are integrated implicitly at velocity level. For each joint the controller works
## out the relative angular velocity an implicit spring-damper step would produce, then applies
## that change to the whole limb below the joint as one rigid rotation about it (a single
## root-to-leaf pass accumulates the changes). Each joint therefore behaves like an independent,
## unconditionally stable spring acting on its true load, so stiff motors hold at 60 Hz whatever
## the mass ratios in the chain. A torque limit keeps every joint overpowerable. The price is
## that motor torques are not reacted on the parent bone.
##
## A second controller keeps the body balanced: an upright servo on the pelvis and a virtual-leg
## support force under it. Scaling `motor_strength` and `balance_strength` to zero turns the
## same rig into a passive ragdoll that only keeps its joint friction.

const GRAVITY := 9.8

@export var upright_kp := 600.0
@export var upright_kd := 50.0
@export var max_upright_torque := 1200.0
@export var height_kp := 110.0
@export var height_kd := 22.0
@export var drive_gain := 8.0
@export var max_drive_accel := 12.0
@export var joint_friction := 2.5    ## 1/s viscous friction at every joint, even when limp.
@export var blunt_threshold := 20.0  ## N*s in one contact before it counts as an impact.

var rig: HumanoidRig
var motor_strength := 1.0    ## 0 = limp, 1 = joints follow the animation.
var balance_strength := 1.0  ## 0 = no balance assistance.
var support := 1.0           ## Share of body weight the legs can carry.
var drive_strength := 1.0    ## Authority of the horizontal locomotion force.
var target_height := Anatomy.STAND_HEIGHT
var heading := 0.0           ## Desired yaw; forward is (-sin, 0, -cos).
var move_velocity := Vector3.ZERO
var grounded := false
var ground_y := 0.0

var _count := 0
var _bones: Array[PhysicalBone3D] = []
var _rids: Array[RID] = []
var _hitboxes: Array[HitboxComponent] = []
var _states: Array[PhysicsDirectBodyState3D] = []
var _parents := PackedInt32Array()
var _anim_index := PackedInt32Array()
var _kp := PackedFloat32Array()
var _kd := PackedFloat32Array()
var _max_torque := PackedFloat32Array()
var _strength := PackedFloat32Array()
var _anchor := PackedVector3Array()   ## Joint position in each bone's local frame.
var _omega := PackedVector3Array()    ## Angular velocities at the start of the tick.
var _spin := PackedVector3Array()     ## Accumulated angular velocity change per bone.
var _push := PackedVector3Array()     ## Accumulated linear velocity change per bone.
var _inertia: Array[Basis] = []       ## Inertia of each joint's attached subtree about the joint, in the bone frame.
var _index: Dictionary[StringName, int] = {}
var _body_inertia := Basis.IDENTITY   ## Whole attached body about the pelvis.
var _supported_mass := 0.0


func setup(p_rig: HumanoidRig) -> void:
	rig = p_rig
	_count = rig.order.size()
	for i in _count:
		var part := rig.order[i]
		var def := rig.defs[part]
		_index[part] = i
		_bones.append(rig.bones[part])
		_rids.append(rig.bones[part].get_rid())
		_hitboxes.append(rig.hitboxes[part])
		_parents.append(_index[def.parent] if def.parent != &"" else -1)
		_anim_index.append(rig.anim_skeleton.find_bone(part))
		_kp.append(def.kp)
		_kd.append(def.kd)
		_max_torque.append(def.torque)
		_strength.append(1.0)
		_anchor.append(-(def.center as Vector3))
		_omega.append(Vector3.ZERO)
		_spin.append(Vector3.ZERO)
		_push.append(Vector3.ZERO)
		_inertia.append(Basis.IDENTITY)
		_states.append(null)
	heading = rig.global_rotation.y
	rebuild_inertia()


func _physics_process(delta: float) -> void:
	if rig == null:
		return
	var driven := motor_strength > 0.001 or balance_strength > 0.001
	var hips := PhysicsServer3D.body_get_direct_state(_rids[0])
	if hips == null or (not driven and hips.sleeping):
		return
	for i in _count:
		var state := PhysicsServer3D.body_get_direct_state(_rids[i])
		_states[i] = state
		_omega[i] = state.angular_velocity if state != null else Vector3.ZERO
	_scan_contacts()
	_probe_ground()
	_drive(delta)
	if balance_strength > 0.001 and grounded and support > 0.0:
		_support(hips)


## Per-part multiplier on the joint motor; 0 leaves a limb hanging limp.
func set_part_strength(part: StringName, value: float) -> void:
	_strength[_index[part]] = value


func hips_position() -> Vector3:
	return _bones[0].global_position


func hips_velocity() -> Vector3:
	return _bones[0].linear_velocity


func hips_height() -> float:
	return _bones[0].global_position.y - ground_y


## Angle between the pelvis and vertical, in radians.
func tilt() -> float:
	return _bones[0].global_basis.y.angle_to(Vector3.UP)


## Instant velocity change on the trunk, used for stagger reactions.
func shove(velocity_change: Vector3) -> void:
	for part: StringName in [Anatomy.HIPS, Anatomy.CHEST]:
		var bone := rig.bones[part]
		bone.apply_central_impulse(velocity_change * bone.mass)


## Recomputes subtree inertias; call after a limb has been severed.
func rebuild_inertia() -> void:
	var body := _attached(Anatomy.HIPS)
	_supported_mass = 0.0
	for part in body:
		_supported_mass += rig.defs[part].mass
	for i in range(1, _count):
		var part := rig.order[i]
		_inertia[i] = _inertia_about(rig.defs[part].joint, _attached(part))
	var hips_def := rig.defs[Anatomy.HIPS]
	_body_inertia = _inertia_about((hips_def.joint as Vector3) + (hips_def.center as Vector3), body)


## Upright servo on the pelvis, then every joint motor, in one root-to-leaf pass.
func _drive(delta: float) -> void:
	var anim := rig.anim_skeleton
	var hips := _states[0]
	_spin[0] = Vector3.ZERO
	_push[0] = Vector3.ZERO
	if balance_strength > 0.001:
		# The same implicit spring-damper as the joints, against the world instead of a parent bone.
		var target := Basis(Vector3.UP, heading) * Basis(anim.get_bone_pose_rotation(_anim_index[0]))
		var basis := hips.transform.basis
		var kp := upright_kp * balance_strength
		var kd := upright_kd * balance_strength
		var wanted := (_omega[0] + delta * kp * _rotation_vector((target * basis.transposed()).get_rotation_quaternion())) \
			/ (1.0 + delta * kd + delta * delta * kp)
		_spin[0] = _limit_torque(wanted - _omega[0], basis, _body_inertia, max_upright_torque * balance_strength, delta)
		if _spin[0].length_squared() > 1e-7:
			hips.angular_velocity = _omega[0] + _spin[0]

	for i in range(1, _count):
		var p := _parents[i]
		var child := _states[i]
		var parent := _states[p]
		if child == null or parent == null or _hitboxes[i].is_severed:
			# A severed limb is its own free body; nothing above it drives it any more.
			_spin[i] = Vector3.ZERO
			_push[i] = Vector3.ZERO
			continue
		var strength := motor_strength * _strength[i]
		var kp := _kp[i] * strength
		var kd := _kd[i] * strength + joint_friction
		var relative := _omega[i] - _omega[p]
		var wanted := relative
		var child_basis := child.transform.basis
		if kp > 0.0:
			# Rotation still missing between the simulated and the animated joint, in the parent frame.
			var parent_basis := parent.transform.basis
			var current := (parent_basis.transposed() * child_basis).get_rotation_quaternion()
			wanted += delta * kp * (parent_basis * _rotation_vector(anim.get_bone_pose_rotation(_anim_index[i]) * current.inverse()))
		# Implicit Euler step of a spring-damper: stable for any stiffness and timestep.
		wanted /= 1.0 + delta * kd + delta * delta * kp
		var change := _limit_torque(wanted - relative, child_basis, _inertia[i], _max_torque[i] * maxf(strength, 0.1), delta)
		# Carry the parent's change down so the limb below this joint turns as one rigid piece.
		var origin := child.transform.origin
		var spin := _spin[p] + change
		var push := _push[p] + _spin[p].cross(origin - parent.transform.origin) + change.cross(origin - child.transform * _anchor[i])
		_spin[i] = spin
		_push[i] = push
		if spin.length_squared() > 1e-7:  # Leave resting bones alone so a limp body can fall asleep.
			child.angular_velocity = _omega[i] + spin
			child.linear_velocity += push


## Virtual legs: a spring-damper holds the pelvis at standing height. It can only push, and only
## as hard as the remaining leg function allows, so a crippled body sinks to the ground.
func _support(hips: PhysicsDirectBodyState3D) -> void:
	var height := hips.transform.origin.y - ground_y
	var accel := height_kp * (target_height - height) - height_kd * hips.linear_velocity.y
	var lift := clampf(GRAVITY + accel, 0.0, GRAVITY * 2.2 * support)
	hips.apply_central_force(Vector3.UP * lift * _supported_mass * balance_strength)
	var velocity := hips.linear_velocity
	var push := (move_velocity - Vector3(velocity.x, 0.0, velocity.z)) * drive_gain
	push.y = 0.0
	hips.apply_central_force(push.limit_length(max_drive_accel) * _supported_mass * balance_strength * drive_strength)


## Axis times angle (shortest way round) for a rotation.
func _rotation_vector(rotation: Quaternion) -> Vector3:
	if rotation.w < 0.0:
		rotation = -rotation
	var angle := 2.0 * acos(clampf(rotation.w, -1.0, 1.0))
	if angle < 0.0005:
		return Vector3.ZERO
	return Vector3(rotation.x, rotation.y, rotation.z).normalized() * angle


## Scales an angular velocity change down so the torque it implies stays under `limit`.
func _limit_torque(change: Vector3, basis: Basis, local_inertia: Basis, limit: float, delta: float) -> Vector3:
	var torque := (basis * (local_inertia * (basis.transposed() * change))) / delta
	var magnitude := torque.length()
	return change * (limit / magnitude) if magnitude > limit else change


func _probe_ground() -> void:
	var origin := _states[0].transform.origin
	var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * (Anatomy.STAND_HEIGHT + 0.6), Layers.SOLID)
	var result := rig.get_world_3d().direct_space_state.intersect_ray(query)
	grounded = not result.is_empty()
	if grounded:
		ground_y = result.position.y


## Converts hard contacts into blunt trauma on the matching hitbox. A collision is usually
## reported as several contact points, so their impulses are summed per bone.
func _scan_contacts() -> void:
	for i in _count:
		var state := _states[i]
		if state == null:
			continue
		var total := 0.0
		var strongest := 0.0
		var best := 0
		for k in state.get_contact_count():
			var impulse := state.get_contact_impulse(k).length()
			total += impulse
			if impulse > strongest:
				strongest = impulse
				best = k
		if total > blunt_threshold:
			_hitboxes[i].apply_blunt(total, state.get_contact_local_position(best),
				state.get_contact_local_normal(best), state.get_contact_collider_object(best) as Node)


## `part` plus everything still attached below it.
func _attached(part: StringName) -> Array[StringName]:
	var result: Array[StringName] = [part]
	var index := 0
	while index < result.size():
		for child: StringName in rig.children_of(result[index]):
			if not rig.hitboxes[child].is_severed:
				result.append(child)
		index += 1
	return result


## Inertia tensor of a group of parts about `pivot`, in rest-pose model axes (parallel-axis theorem).
func _inertia_about(pivot: Vector3, parts: Array[StringName]) -> Basis:
	var xx := 0.0
	var yy := 0.0
	var zz := 0.0
	var xy := 0.0
	var xz := 0.0
	var yz := 0.0
	for part in parts:
		var def := rig.defs[part]
		var m: float = def.mass
		var own := _own_inertia(def)
		var c: Vector3 = (def.joint as Vector3) + (def.center as Vector3) - pivot
		xx += own.x + m * (c.y * c.y + c.z * c.z)
		yy += own.y + m * (c.x * c.x + c.z * c.z)
		zz += own.z + m * (c.x * c.x + c.y * c.y)
		xy -= m * c.x * c.y
		xz -= m * c.x * c.z
		yz -= m * c.y * c.z
	return Basis(Vector3(xx, xy, xz), Vector3(xy, yy, yz), Vector3(xz, yz, zz))


func _own_inertia(def: Dictionary) -> Vector3:
	var m: float = def.mass
	if def.shape == "capsule":
		var r: float = def.radius
		var h: float = def.height
		var across := m * (3.0 * r * r + h * h) / 12.0
		return Vector3(across, 0.5 * m * r * r, across)
	var s: Vector3 = def.size
	return Vector3(s.y * s.y + s.z * s.z, s.x * s.x + s.z * s.z, s.x * s.x + s.y * s.y) * m / 12.0
