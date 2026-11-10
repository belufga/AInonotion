class_name Gib
extends RigidBody3D
## Pooled meat, bone or organ giblet. Bounces with high friction, stains where it lands and
## smears while it slides, then goes to sleep.

enum Kind { MEAT, BONE, ORGAN }

const STAIN_SPACING := 0.3
const MAX_LIFE := 20.0

var active := false

var _mesh: MeshInstance3D
var _shape: BoxShape3D
var _stains_left := 0
var _last_stain := Vector3.ZERO
var _life := 0.0


func _init() -> void:
	collision_layer = 0
	collision_mask = 0
	freeze = true
	visible = false
	contact_monitor = true
	max_contacts_reported = 2
	mass = 0.4
	var material := PhysicsMaterial.new()
	material.friction = 0.9
	material.bounce = 0.25
	physics_material_override = material
	set_meta(BallisticMaterial.META_SURFACE, &"flesh")
	_mesh = MeshInstance3D.new()
	add_child(_mesh)
	_shape = BoxShape3D.new()
	var collider := CollisionShape3D.new()
	collider.shape = _shape
	add_child(collider)
	set_physics_process(false)


func launch(kind: Kind, mesh: Mesh, extents: Vector3, origin: Vector3, velocity: Vector3) -> void:
	_mesh.mesh = mesh
	_mesh.scale = extents
	_shape.size = extents
	global_transform = Transform3D(Basis.from_euler(Vector3(randf(), randf(), randf()) * TAU), origin)
	collision_layer = Layers.GIBS
	collision_mask = Layers.SOLID
	freeze = false
	linear_velocity = velocity
	angular_velocity = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 24.0
	visible = true
	active = true
	_stains_left = 2 if kind == Kind.BONE else 6
	_last_stain = origin
	_life = 0.0
	set_physics_process(true)


func retire() -> void:
	active = false
	visible = false
	freeze = true
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	_life += delta
	if _stains_left <= 0 or _life > MAX_LIFE or sleeping:
		set_physics_process(false)
		return
	if get_contact_count() > 0 and global_position.distance_to(_last_stain) > STAIN_SPACING:
		_stains_left -= 1
		_last_stain = global_position
		BloodFX.gib_stain(global_position, linear_velocity)
