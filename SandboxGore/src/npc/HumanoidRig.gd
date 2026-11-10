class_name HumanoidRig
extends Node3D
## Physical bone / ragdoll setup.
##
## Builds, from the Anatomy table: the simulated Skeleton3D with a PhysicalBoneSimulator3D and one
## PhysicalBone3D per body part (collision shape, mass, 6DOF joint with anatomical limits), a
## second "AnimRig" Skeleton3D that only carries the animated target pose, the visual meshes,
## a HitboxComponent per bone and the OrganVolume3D areas inside them.

const SKIN_TONES := [Color(0.94, 0.78, 0.66), Color(0.85, 0.65, 0.5), Color(0.67, 0.47, 0.34), Color(0.45, 0.3, 0.22)]
const SHIRTS := [Color(0.75, 0.75, 0.72), Color(0.25, 0.4, 0.62), Color(0.55, 0.2, 0.2), Color(0.3, 0.45, 0.3), Color(0.85, 0.7, 0.3)]
const PANTS := [Color(0.18, 0.2, 0.28), Color(0.3, 0.27, 0.22), Color(0.12, 0.12, 0.13), Color(0.35, 0.38, 0.42)]
const TORSO_VISUAL_SCALE := 1.18  ## Torso boxes are drawn as slightly larger ellipsoids.
const AXES := ["x", "y", "z"]
const META_FROZEN := &"frozen"

var skeleton: Skeleton3D
var anim_skeleton: Skeleton3D
var simulator: PhysicalBoneSimulator3D
var order: Array[StringName] = []  ## Part names, parents first.
var defs: Dictionary[StringName, Dictionary] = {}
var bones: Dictionary[StringName, PhysicalBone3D] = {}
var hitboxes: Dictionary[StringName, HitboxComponent] = {}
var organs: Array[OrganVolume3D] = []
var total_mass := 0.0

var _children: Dictionary[StringName, Array] = {}

static var _materials: Dictionary = {}
static var _unit_sphere: SphereMesh


func build(health: HealthComponent, vitals: VitalsComponent, palette: Dictionary = {}) -> void:
	var parts := Anatomy.humanoid()
	skeleton = _make_skeleton("Skeleton", parts)
	anim_skeleton = _make_skeleton("AnimRig", parts)
	add_child(skeleton)
	add_child(anim_skeleton)
	simulator = PhysicalBoneSimulator3D.new()
	simulator.name = "PhysicalBoneSimulator"
	skeleton.add_child(simulator)

	var colors := {
		"skin": palette.get("skin", SKIN_TONES.pick_random()),
		"shirt": palette.get("shirt", SHIRTS.pick_random()),
		"pants": palette.get("pants", PANTS.pick_random()),
		"shoes": palette.get("shoes", Color(0.1, 0.09, 0.08)),
	}
	for def in parts:
		var part: StringName = def.name
		order.append(part)
		defs[part] = def
		_children[part] = []
		if def.parent != &"":
			_children[def.parent].append(part)
		total_mass += def.mass

		# A bone must enter the tree after its parent so the joint can find the parent body.
		var bone := _make_bone(def)
		simulator.add_child(bone)
		_apply_limits(bone, def)
		bones[part] = bone
		_add_visuals(bone, def, colors)

		var hitbox := HitboxComponent.new()
		hitbox.name = "HitboxComponent"
		hitbox.configure(def)
		hitbox.bone = bone
		hitbox.health = health
		hitbox.vitals = vitals
		bone.add_child(hitbox)
		bone.set_meta(HitboxComponent.META_KEY, hitbox)
		hitboxes[part] = hitbox
		for organ_def: Dictionary in def.organs:
			_add_organ(bone, hitbox, organ_def, vitals)

	# Jointed physical bones collide with each other by default, which fights the joints.
	for i in order.size():
		for j in range(i + 1, order.size()):
			bones[order[i]].add_collision_exception_with(bones[order[j]])
			bones[order[j]].add_collision_exception_with(bones[order[i]])


func start_simulation() -> void:
	simulator.physical_bones_start_simulation()
	for bone: PhysicalBone3D in bones.values():
		# Contact impulses feed the blunt-trauma model.
		PhysicsServer3D.body_set_max_contacts_reported(bone.get_rid(), 3)


## Releases the joint between `part` and its parent.
func detach(part: StringName) -> void:
	var bone := bones[part]
	# Setting joint_type to NONE leaves the old constraint alive in the physics server,
	# so the 6DOF joint is opened on every axis instead.
	for axis: String in AXES:
		bone.set("joint_constraints/%s/linear_limit_enabled" % axis, false)
		bone.set("joint_constraints/%s/angular_limit_enabled" % axis, false)


## Removes a part from play (gibbed torso): hidden, non-colliding and no longer simulated.
func destroy_part(part: StringName) -> void:
	var bone := bones[part]
	if defs[part].parent != &"":
		detach(part)
	for child in bone.get_children():
		if child is MeshInstance3D or child is StumpCap or child is Decal:
			child.visible = false
		elif child is OrganVolume3D:
			child.collision_layer = 0
	bone.collision_layer = 0
	bone.collision_mask = 0
	hitboxes[part].detached = true
	PhysicsServer3D.body_set_mode(bone.get_rid(), PhysicsServer3D.BODY_MODE_STATIC)


func joint_position(part: StringName) -> Vector3:
	return bones[part].global_transform * (-(defs[part].center as Vector3))


func children_of(part: StringName) -> Array:
	return _children[part]


## `part` and every part below it.
func subtree(part: StringName) -> Array[StringName]:
	var result: Array[StringName] = [part]
	var index := 0
	while index < result.size():
		for child: StringName in _children[result[index]]:
			result.append(child)
		index += 1
	return result


## How far beyond the joint the severed limb's own end cap sits.
func cap_offset_child(part: StringName) -> float:
	var def := defs[part]
	if def.shape != "capsule":
		return 0.0
	return maxf(def.height * 0.5 - (def.center as Vector3).length(), 0.0) + 0.003


## How far beyond the joint the stump on the remaining body sits, so it clears the parent's mesh.
func cap_offset_parent(part: StringName) -> float:
	var def := defs[part]
	var parent := defs[def.parent as StringName]
	var from_center: Vector3 = (def.joint as Vector3) - ((parent.joint as Vector3) + (parent.center as Vector3))
	if parent.shape == "capsule":
		return maxf(parent.height * 0.5 - from_center.length(), 0.0) + 0.003
	# Exit distance from the parent's visual ellipsoid along the limb direction.
	var semi: Vector3 = (parent.size as Vector3) * TORSO_VISUAL_SCALE * 0.5
	var o := from_center / semi
	var d := (def.center as Vector3).normalized() / semi
	var a := d.dot(d)
	var b := o.dot(d)
	var disc := b * b - a * (o.dot(o) - 1.0)
	if disc < 0.0:
		return 0.004
	return maxf((-b + sqrt(disc)) / a, 0.0) + 0.004


## Toolgun freeze for a ragdoll bone; PhysicalBone3D has no `freeze` property of its own.
static func set_bone_frozen(bone: PhysicalBone3D, frozen: bool) -> void:
	bone.set_meta(META_FROZEN, frozen)
	PhysicsServer3D.body_set_mode(bone.get_rid(),
		PhysicsServer3D.BODY_MODE_STATIC if frozen else PhysicsServer3D.BODY_MODE_RIGID)
	if not frozen:
		PhysicsServer3D.body_set_state(bone.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING, false)


static func is_bone_frozen(bone: PhysicalBone3D) -> bool:
	return bone.get_meta(META_FROZEN, false)


func _make_skeleton(p_name: String, parts: Array[Dictionary]) -> Skeleton3D:
	var result := Skeleton3D.new()
	result.name = p_name
	var joints := {}
	for def in parts:
		var index := result.add_bone(def.name)
		var origin: Vector3 = def.joint
		if def.parent != &"":
			result.set_bone_parent(index, result.find_bone(def.parent))
			origin -= joints[def.parent]
		joints[def.name] = def.joint
		result.set_bone_rest(index, Transform3D(Basis.IDENTITY, origin))
	result.reset_bone_poses()
	return result


func _make_bone(def: Dictionary) -> PhysicalBone3D:
	var bone := PhysicalBone3D.new()
	bone.name = "Bone" + String(def.name)
	bone.bone_name = def.name
	bone.joint_type = PhysicalBone3D.JOINT_TYPE_NONE if def.parent == &"" else PhysicalBone3D.JOINT_TYPE_6DOF
	bone.body_offset = Transform3D(Basis.IDENTITY, def.center)
	bone.mass = def.mass
	bone.friction = 0.6 if def.look == "shoes" else 0.85
	bone.bounce = 0.0
	bone.linear_damp = 0.05
	bone.angular_damp = 0.8
	bone.can_sleep = true
	bone.collision_layer = Layers.BODY
	bone.collision_mask = Layers.WORLD | Layers.PROPS | Layers.BODY | Layers.PROJECTILES
	bone.set_meta(BallisticMaterial.META_SURFACE, &"flesh")
	var collider := CollisionShape3D.new()
	if def.shape == "capsule":
		var capsule := CapsuleShape3D.new()
		capsule.radius = def.radius
		capsule.height = def.height
		collider.shape = capsule
	else:
		var box := BoxShape3D.new()
		box.size = def.size
		collider.shape = box
	bone.add_child(collider)
	return bone


func _apply_limits(bone: PhysicalBone3D, def: Dictionary) -> void:
	if def.parent == &"":
		return
	var low: Vector3 = def.lim_min
	var high: Vector3 = def.lim_max
	for i in 3:
		var prefix := "joint_constraints/%s/" % AXES[i]
		bone.set(prefix + "angular_limit_enabled", true)
		# PhysicalBone3D limits run opposite to a right-handed rotation about the joint axis,
		# so the anatomical range [low, high] is stored as [-high, -low].
		bone.set(prefix + "angular_limit_lower", -high[i])
		bone.set(prefix + "angular_limit_upper", -low[i])


func _add_organ(bone: PhysicalBone3D, hitbox: HitboxComponent, organ_def: Dictionary, vitals: VitalsComponent) -> void:
	var organ := OrganVolume3D.new()
	organ.name = String(organ_def.name)
	organ.organ_name = organ_def.name
	organ.kind = organ_def.kind
	organ.lung_index = organ_def.get("lung_index", 0)
	organ.toughness = organ_def.toughness
	organ.bleed_rate = organ_def.bleed
	organ.arterial = organ_def.arterial
	organ.path_length = organ_def.path
	organ.position = organ_def.pos
	organ.vitals = vitals
	organ.hitbox = hitbox
	var collider := CollisionShape3D.new()
	if organ_def.height > 0.0:
		var capsule := CapsuleShape3D.new()
		capsule.radius = organ_def.radius
		capsule.height = organ_def.height
		collider.shape = capsule
	else:
		var sphere := SphereShape3D.new()
		sphere.radius = organ_def.radius
		collider.shape = sphere
	organ.add_child(collider)
	bone.add_child(organ)
	hitbox.organs.append(organ)
	organs.append(organ)


func _add_visuals(bone: PhysicalBone3D, def: Dictionary, colors: Dictionary) -> void:
	var material := _material(colors[def.look])
	var skin := _material(colors.skin)
	if def.name == Anatomy.HEAD:
		_add_mesh(bone, _sphere(), skin, Vector3(0.0, 0.03, 0.0), Vector3.ONE * 0.21)
		var neck := CylinderMesh.new()
		neck.top_radius = 0.045
		neck.bottom_radius = 0.05
		neck.height = 0.12
		neck.radial_segments = 12
		_add_mesh(bone, neck, skin, Vector3(0.0, -0.095, 0.0))
		var eye := _material(Color(0.05, 0.05, 0.06))
		for x: float in [-0.036, 0.036]:
			_add_mesh(bone, _sphere(), eye, Vector3(x, 0.045, -0.092), Vector3.ONE * 0.026)
	elif def.shape == "capsule":
		var capsule := CapsuleMesh.new()
		capsule.radius = def.radius
		capsule.height = def.height
		capsule.radial_segments = 12
		capsule.rings = 4
		_add_mesh(bone, capsule, material)
		if String(def.name).begins_with("LowerArm"):
			_add_mesh(bone, _sphere(), skin, Vector3(0.0, -0.165, 0.0), Vector3(0.075, 0.1, 0.05))
	elif def.look == "shoes":
		var shoe := BoxMesh.new()
		shoe.size = def.size
		_add_mesh(bone, shoe, material)
	else:
		_add_mesh(bone, _sphere(), material, Vector3.ZERO, (def.size as Vector3) * TORSO_VISUAL_SCALE)


func _add_mesh(bone: Node3D, mesh: Mesh, material: Material, offset := Vector3.ZERO, mesh_scale := Vector3.ONE) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = offset
	instance.scale = mesh_scale
	instance.layers = Layers.VIS_WORLD
	bone.add_child(instance)


static func _sphere() -> SphereMesh:
	if _unit_sphere == null:
		_unit_sphere = SphereMesh.new()
		_unit_sphere.radius = 0.5
		_unit_sphere.height = 1.0
		_unit_sphere.radial_segments = 16
		_unit_sphere.rings = 8
	return _unit_sphere


static func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.75
		_materials[color] = material
	return _materials[color]
