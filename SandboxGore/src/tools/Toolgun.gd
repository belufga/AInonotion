class_name Toolgun
extends WeaponBase3D
## Sandbox toolgun, the "Reality Crusher": a raycast beam from the first-person camera with six
## modes. Grab is a physgun (PID-tracked force at the grabbed point, distance on the wheel,
## rotation with E + mouse); Freeze toggles bodies static in mid-air; Weld and Pin build
## Generic6DOFJoint3D / PinJoint3D constraints between two picked bodies; Spawn and Remove create
## and delete entities. Ragdoll bones are valid targets for every mode.

enum Mode { GRAB, FREEZE, WELD, PIN, SPAWN, REMOVE }

signal mode_changed(mode: Mode)

const REACH := 80.0
const MIN_HOLD := 1.2
const MAX_HOLD := 45.0
const MAX_PULL_ACCEL := 180.0
const LIMB_MASS_FACTOR := 6.0  ## A grabbed limb drags the rest of the ragdoll behind it.
const META_BODIES := &"constrained_bodies"
const MODES: Array[Dictionary] = [
	{"label": "Grab", "color": Color(0.2, 0.6, 1.0), "hint": "LMB hold: grab   wheel: push / pull   E + mouse: rotate   RMB: freeze in place"},
	{"label": "Freeze", "color": Color(0.45, 0.85, 1.0), "hint": "LMB: freeze / unfreeze the target   RMB: unfreeze"},
	{"label": "Weld", "color": Color(1.0, 0.72, 0.2), "hint": "LMB: pick two bodies to weld   RMB: remove the target's joints"},
	{"label": "Pin", "color": Color(0.55, 0.95, 0.4), "hint": "LMB: pick two bodies to pin   RMB: remove the target's joints"},
	{"label": "Spawn", "color": Color(0.75, 0.5, 1.0), "hint": "LMB: spawn   RMB: delete the target   Tab: choose what to spawn"},
	{"label": "Remove", "color": Color(1.0, 0.3, 0.3), "hint": "LMB / RMB: delete the target"},
]

var mode := Mode.GRAB
var spawn_id: StringName = &"civilian"
var rotating := false  ## E held: mouse motion turns the held body instead of the camera.

var _held: PhysicsBody3D
var _held_local := Vector3.ZERO      ## Grabbed point in the body's own space.
var _hold_distance := 3.0
var _hold_rotation := Basis.IDENTITY  ## Held body's orientation relative to the camera.
var _pid := PIDController.new(60.0, 20.0, 14.0, 2.0)
var _first_body: PhysicsBody3D
var _beam: MeshInstance3D
var _beam_material: StandardMaterial3D
var _beam_target := Vector3.ZERO
var _beam_left := 0.0


func _init() -> void:
	display_name = "Toolgun"
	weapon_id = &"toolgun"
	uses_ammo = false
	can_aim = false
	hip_offset = Vector3(0.17, -0.14, -0.34)
	sound = &"tool"


func _setup() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.025, 0.025, 1.0)
	_beam_material = StandardMaterial3D.new()
	_beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam = MeshInstance3D.new()
	_beam.mesh = mesh
	_beam.material_override = _beam_material
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.top_level = true
	_beam.visible = false
	add_child(_beam)


func _physics_process(delta: float) -> void:
	super(delta)
	_update_grab(delta)


# --- input ---------------------------------------------------------------------------------

func trigger_pressed() -> void:
	if wielder == null:
		return
	var hit := _raycast()
	if hit.is_empty():
		return
	_flash_beam(hit.position)
	match mode:
		Mode.GRAB:
			_begin_grab(hit)
		Mode.FREEZE:
			var body := hit.collider as PhysicsBody3D
			if body != null:
				set_frozen(body, not is_frozen(body))
		Mode.WELD, Mode.PIN:
			_constrain(hit)
		Mode.SPAWN:
			_spawn(hit)
		Mode.REMOVE:
			_remove(hit.collider)


func trigger_released() -> void:
	if mode == Mode.GRAB:
		release()


func secondary_pressed() -> void:
	if wielder == null:
		return
	if _held != null:
		# Physgun classic: pin the held object in the air where it is.
		var body := _held
		release()
		set_frozen(body, true)
		return
	var hit := _raycast()
	if hit.is_empty():
		return
	_flash_beam(hit.position)
	match mode:
		Mode.FREEZE:
			var body := hit.collider as PhysicsBody3D
			if body != null:
				set_frozen(body, false)
		Mode.WELD, Mode.PIN:
			remove_constraints(hit.collider as PhysicsBody3D)
		Mode.SPAWN, Mode.REMOVE:
			_remove(hit.collider)


func secondary_released() -> void:
	pass


func unequip() -> void:
	release()
	_first_body = null
	rotating = false
	_beam.visible = false
	super()


## Mouse wheel: push or pull the held body along the beam.
func scroll(direction: int) -> bool:
	if _held == null:
		return false
	_hold_distance = clampf(_hold_distance * (1.12 if direction > 0 else 1.0 / 1.12), MIN_HOLD, MAX_HOLD)
	return true


## Mouse motion while `rotating`: turn the held rigid body about the camera's axes.
func rotate_input(relative: Vector2) -> void:
	if _held is RigidBody3D:
		_hold_rotation = Basis(Vector3.UP, relative.x * 0.01) * Basis(Vector3.RIGHT, relative.y * 0.01) * _hold_rotation


func set_mode(next: Mode) -> void:
	if next == mode:
		return
	release()
	_first_body = null
	mode = next
	Sfx.play(&"click", global_position, -6.0)
	mode_changed.emit(mode)


func is_holding() -> bool:
	return _held != null


func ammo_text() -> String:
	var text: String = MODES[mode].label
	if mode == Mode.SPAWN:
		text += ": " + String(SpawnCatalog.find(spawn_id).label)
	return text


func hud_hint() -> String:
	if (mode == Mode.WELD or mode == Mode.PIN) and is_instance_valid(_first_body):
		return "First body picked - LMB on the second body (or the world)"
	return MODES[mode].hint


func update_view(delta: float, look_rate: Vector2, speed: float, grounded: bool) -> void:
	super(delta, look_rate, speed, grounded)
	_beam_left -= delta
	var holding := is_instance_valid(_held)
	_beam.visible = visible and (holding or _beam_left > 0.0)
	if not _beam.visible:
		return
	var from := get_muzzle_position()
	var to: Vector3 = _held.global_transform * _held_local if holding else _beam_target
	var span := to - from
	var length := span.length()
	if length < 0.05:
		_beam.visible = false
		return
	var direction := span / length
	var up := Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT
	_beam.global_transform = Transform3D(Basis.looking_at(direction, up).scaled_local(Vector3(1.0, 1.0, length)), from + span * 0.5)
	var color: Color = MODES[mode].color
	_beam_material.albedo_color = Color(color.r, color.g, color.b, 0.75 if holding else clampf(_beam_left / 0.15, 0.0, 1.0) * 0.75)


# --- grab ----------------------------------------------------------------------------------

func release() -> void:
	if _held == null:
		return
	var humanoid := Layers.entity_root(_held) as Humanoid if is_instance_valid(_held) else null
	if humanoid != null:
		humanoid.brain.set_held(false)
	_held = null


func _begin_grab(hit: Dictionary) -> void:
	var body := hit.collider as PhysicsBody3D
	if not (body is RigidBody3D or body is PhysicalBone3D):
		return
	if is_frozen(body):
		set_frozen(body, false)
	var aim: Transform3D = wielder.get_aim_transform()
	_held = body
	_held_local = body.global_transform.affine_inverse() * (hit.position as Vector3)
	_hold_distance = clampf(aim.origin.distance_to(hit.position), MIN_HOLD, MAX_HOLD)
	_hold_rotation = aim.basis.inverse() * body.global_basis
	_pid.reset()
	var humanoid := Layers.entity_root(body) as Humanoid
	if humanoid != null:
		humanoid.brain.set_held(true)
	Sfx.play(sound, hit.position, -8.0)


func _update_grab(delta: float) -> void:
	if _held == null:
		return
	if not is_instance_valid(_held) or wielder == null:
		_held = null
		return
	var state := PhysicsServer3D.body_get_direct_state(_held.get_rid())
	if state == null:
		return
	var aim: Transform3D = wielder.get_aim_transform()
	var target := aim.origin - aim.basis.z * _hold_distance
	var xform := state.transform
	var arm := xform * _held_local - xform.origin
	var grip_velocity := state.linear_velocity + state.angular_velocity.cross(arm)
	# PID on the grabbed point: P pulls it to the beam end, D damps it, I cancels the sag of gravity.
	var accel := _pid.step(target - (xform.origin + arm), grip_velocity, delta).limit_length(MAX_PULL_ACCEL)
	var mass := 1.0 / maxf(state.inverse_mass, 0.0001)
	if _held is PhysicalBone3D:
		mass *= LIMB_MASS_FACTOR
	state.apply_force(accel * mass, arm)
	if _held is RigidBody3D:
		# Rigid props keep their orientation relative to the camera (implicit spring-damper servo).
		var error := (aim.basis * _hold_rotation * xform.basis.transposed()).get_rotation_quaternion()
		if error.w < 0.0:
			error = -error
		var angle := 2.0 * acos(clampf(error.w, -1.0, 1.0))
		var correction := Vector3.ZERO if angle < 0.0005 else Vector3(error.x, error.y, error.z).normalized() * angle
		state.angular_velocity = (state.angular_velocity + delta * 140.0 * correction) / (1.0 + delta * 24.0 + delta * delta * 140.0)


# --- freeze --------------------------------------------------------------------------------

static func set_frozen(body: PhysicsBody3D, frozen: bool) -> void:
	if body is RigidBody3D:
		body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		body.freeze = frozen
		if not frozen:
			body.sleeping = false
	elif body is PhysicalBone3D:
		HumanoidRig.set_bone_frozen(body, frozen)


static func is_frozen(body: PhysicsBody3D) -> bool:
	if body is RigidBody3D:
		return body.freeze
	if body is PhysicalBone3D:
		return HumanoidRig.is_bone_frozen(body)
	return false


# --- constraints ---------------------------------------------------------------------------

## Two clicks: the first picks a dynamic body, the second picks what to attach it to. The joint
## is created at the second contact point with its Z axis along the contact normal.
func _constrain(hit: Dictionary) -> void:
	var body := hit.collider as PhysicsBody3D
	if body == null:
		return
	if not is_instance_valid(_first_body):
		if body is RigidBody3D or body is PhysicalBone3D:
			_first_body = body
			Sfx.play(&"click", hit.position, -4.0)
		return
	if body == _first_body:
		_first_body = null
		return
	var joint: Joint3D
	if mode == Mode.WELD:
		joint = Generic6DOFJoint3D.new()  # All six axes are locked by default: a rigid weld.
		joint.name = "Weld"
	else:
		joint = PinJoint3D.new()
		joint.name = "Pin"
	SpawnCatalog.container(get_tree()).add_child(joint, true)
	var normal: Vector3 = hit.normal
	var up := Vector3.UP if absf(normal.y) < 0.99 else Vector3.RIGHT
	joint.global_transform = Transform3D(Basis.looking_at(-normal, up), hit.position)
	joint.node_a = joint.get_path_to(_first_body)
	joint.node_b = joint.get_path_to(body)
	joint.set_meta(META_BODIES, [_first_body, body])
	# A joint must not outlive either of its bodies.
	_first_body.tree_exiting.connect(joint.queue_free)
	body.tree_exiting.connect(joint.queue_free)
	if _first_body is RigidBody3D:
		_first_body.sleeping = false
	_first_body = null
	Sfx.play(sound, hit.position, -6.0)


func remove_constraints(body: PhysicsBody3D) -> int:
	var removed := 0
	if body == null:
		return removed
	for node in SpawnCatalog.container(get_tree()).get_children():
		if node is Joint3D and node.has_meta(META_BODIES) and (node.get_meta(META_BODIES) as Array).has(body):
			node.queue_free()
			removed += 1
	return removed


# --- spawn / remove ------------------------------------------------------------------------

func _spawn(hit: Dictionary) -> void:
	var aim: Transform3D = wielder.get_aim_transform()
	var toward := aim.origin - (hit.position as Vector3)
	var yaw := atan2(-toward.x, -toward.z)  # Spawned characters face the player.
	var position: Vector3 = hit.position
	if (hit.normal as Vector3).y < 0.5:
		position += (hit.normal as Vector3) * 0.6  # Aimed at a wall: step away from it.
	SpawnCatalog.spawn(spawn_id, position, yaw, SpawnCatalog.container(get_tree()))
	Sfx.play(sound, hit.position, -6.0)


func _remove(collider: Object) -> void:
	var entity := Layers.entity_root(collider as Node)
	if entity != null:
		entity.queue_free()
		Sfx.play(sound, global_position, -6.0, 0.7)
	elif collider is Gib:
		collider.retire()


func _raycast() -> Dictionary:
	var aim: Transform3D = wielder.get_aim_transform()
	var query := PhysicsRayQueryParameters3D.create(aim.origin, aim.origin - aim.basis.z * REACH, Layers.TOOL)
	return get_world_3d().direct_space_state.intersect_ray(query)


func _flash_beam(target: Vector3) -> void:
	_beam_target = target
	_beam_left = 0.15
