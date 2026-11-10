class_name ProceduralAnimator
extends Node
## Procedural animation source for the active ragdoll.
##
## Writes joint rotations onto the AnimRig skeleton each tick: idle breathing, a walk cycle
## driven by actual forward speed, weapon aiming, cowering and prone crawling. The physical bones
## never read these poses directly; ActiveRagdoll's motors chase them. An AnimationPlayer could
## drive the same skeleton instead without touching the ragdoll code.

enum Pose { STAND, COWER, CRAWL }

const STRIDE := 1.35      ## Metres travelled per full walk cycle.
const BLEND_RATE := 12.0  ## 1/s; how quickly joint targets ease toward a new pose.

var rig: HumanoidRig
var pose := Pose.STAND
var speed := 0.0            ## Forward speed in m/s; advances the walk cycle.
var aim_weight := 0.0
var aim_target := Vector3.ZERO
var tremble := 0.0
var height_offset := 0.0    ## Walk bob, added to the ragdoll's hip height target.

var _phase := 0.0
var _time := 0.0
var _euler: Dictionary[StringName, Vector3] = {}
var _current: Dictionary[StringName, Quaternion] = {}
var _bone_index: Dictionary[StringName, int] = {}


func setup(p_rig: HumanoidRig) -> void:
	rig = p_rig
	for part in rig.order:
		_euler[part] = Vector3.ZERO
		_current[part] = Quaternion.IDENTITY
		_bone_index[part] = rig.anim_skeleton.find_bone(part)


func update(delta: float, heading: float) -> void:
	_time += delta
	for part in rig.order:
		_euler[part] = Vector3.ZERO
	height_offset = 0.0
	match pose:
		Pose.STAND:
			_pose_stand(delta)
		Pose.COWER:
			_pose_cower()
		Pose.CRAWL:
			_pose_crawl(delta)

	var aim_arm := Anatomy.limb("UpperArm", Anatomy.RIGHT)
	var aim_rotation := Quaternion.IDENTITY
	if aim_weight > 0.001:
		aim_rotation = _aim_rotation(heading)
	var blend := 1.0 - exp(-BLEND_RATE * delta)
	var skeleton := rig.anim_skeleton
	for part in rig.order:
		var target := _target(part)
		if part == aim_arm and aim_weight > 0.001:
			target = target.slerp(aim_rotation, aim_weight)
		var rotation := _current[part].slerp(target, blend)
		_current[part] = rotation
		skeleton.set_bone_pose_rotation(_bone_index[part], rotation)


func _target(part: StringName) -> Quaternion:
	var e := _euler[part]
	return Quaternion.from_euler(Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z)))


func _pose_stand(delta: float) -> void:
	_phase = fmod(_phase + delta * TAU * absf(speed) / STRIDE, TAU)
	var walk := clampf(absf(speed) / 1.4, 0.0, 1.3)
	var breath := sin(_time * 1.6)
	for side: int in [Anatomy.LEFT, Anatomy.RIGHT]:
		var phase := _phase if side < 0 else _phase + PI
		var swing := sin(phase)
		var lift := maxf(cos(phase), 0.0)  # The knee folds while the leg swings forward.
		var hip := 28.0 * swing * walk + 4.0 * walk
		var knee := -(4.0 + 52.0 * lift * walk)
		_euler[Anatomy.limb("UpperLeg", side)] = Vector3(hip, 0.0, 2.0 * side)
		_euler[Anatomy.limb("LowerLeg", side)] = Vector3(knee, 0.0, 0.0)
		# Counter-rotate the ankle so the sole stays level; a tilted foot would pry the body over.
		_euler[Anatomy.limb("Foot", side)] = Vector3(clampf(-(hip + knee), -40.0, 25.0), 0.0, 0.0)
		_euler[Anatomy.limb("UpperArm", side)] = Vector3(-22.0 * swing * walk, 0.0, 5.0 * side)
		_euler[Anatomy.limb("LowerArm", side)] = Vector3(12.0 + 18.0 * walk, 0.0, 0.0)
	_euler[Anatomy.HIPS] = Vector3(0.0, 4.0 * sin(_phase) * walk, 2.0 * cos(_phase) * walk)
	_euler[Anatomy.SPINE] = Vector3(-2.0 * walk + 0.8 * breath, 5.0 * sin(_phase) * walk, 0.0)
	_euler[Anatomy.CHEST] = Vector3(breath, -4.0 * sin(_phase) * walk, 0.0)
	height_offset = 0.015 * cos(2.0 * _phase) * walk
	if aim_weight > 0.001:
		# Support hand comes up and across to steady the rifle.
		var left_arm := Vector3(60.0, 0.0, 18.0)
		_euler[Anatomy.limb("UpperArm", Anatomy.LEFT)] = _euler[Anatomy.limb("UpperArm", Anatomy.LEFT)].lerp(left_arm, aim_weight)
		_euler[Anatomy.limb("LowerArm", Anatomy.LEFT)] = Vector3(lerpf(12.0, 70.0, aim_weight), 0.0, 0.0)
		_euler[Anatomy.limb("LowerArm", Anatomy.RIGHT)] = Vector3(lerpf(12.0, 8.0, aim_weight), 0.0, 0.0)


func _pose_cower() -> void:
	var shake := tremble * 3.0
	_euler[Anatomy.HIPS] = Vector3(-15.0, 0.0, 0.0)
	_euler[Anatomy.SPINE] = Vector3(-30.0 + shake * sin(_time * 31.0), 0.0, 0.0)
	_euler[Anatomy.CHEST] = Vector3(-20.0, 0.0, 0.0)
	_euler[Anatomy.HEAD] = Vector3(-25.0, 0.0, 0.0)
	for side: int in [Anatomy.LEFT, Anatomy.RIGHT]:
		_euler[Anatomy.limb("UpperLeg", side)] = Vector3(95.0, 0.0, 6.0 * side)
		_euler[Anatomy.limb("LowerLeg", side)] = Vector3(-125.0, 0.0, 0.0)
		_euler[Anatomy.limb("Foot", side)] = Vector3(25.0, 0.0, 0.0)
		_euler[Anatomy.limb("UpperArm", side)] = Vector3(150.0 + shake * sin(_time * 27.0 + side), 0.0, 25.0 * side)
		_euler[Anatomy.limb("LowerArm", side)] = Vector3(125.0, 0.0, 0.0)


func _pose_crawl(delta: float) -> void:
	if absf(speed) > 0.05:
		_phase = fmod(_phase + delta * 3.2, TAU)
	_euler[Anatomy.HIPS] = Vector3(-78.0, 0.0, 0.0)
	_euler[Anatomy.SPINE] = Vector3(8.0, 0.0, 0.0)
	_euler[Anatomy.CHEST] = Vector3(10.0, 0.0, 0.0)
	_euler[Anatomy.HEAD] = Vector3(35.0, 0.0, 0.0)
	for side: int in [Anatomy.LEFT, Anatomy.RIGHT]:
		var reach := sin(_phase if side < 0 else _phase + PI)
		_euler[Anatomy.limb("UpperArm", side)] = Vector3(150.0 + 25.0 * reach, 0.0, 18.0 * side)
		_euler[Anatomy.limb("LowerArm", side)] = Vector3(35.0 + 35.0 * maxf(-reach, 0.0), 0.0, 0.0)
		_euler[Anatomy.limb("UpperLeg", side)] = Vector3(5.0, 0.0, 4.0 * side)
		_euler[Anatomy.limb("LowerLeg", side)] = Vector3(-10.0, 0.0, 0.0)


## Shoulder rotation, in the chest frame, that points the hanging arm at `aim_target`.
func _aim_rotation(heading: float) -> Quaternion:
	var to_target := aim_target - rig.joint_position(Anatomy.limb("UpperArm", Anatomy.RIGHT))
	if to_target.length_squared() < 0.01:
		return Quaternion.IDENTITY
	var torso := Basis(Vector3.UP, heading) * Basis(_target(Anatomy.HIPS) * _target(Anatomy.SPINE) * _target(Anatomy.CHEST))
	var local := (torso.transposed() * to_target).normalized()
	if local.dot(Vector3.DOWN) < -0.999:
		return Quaternion(Vector3.RIGHT, PI)
	return Quaternion(Vector3.DOWN, local)
