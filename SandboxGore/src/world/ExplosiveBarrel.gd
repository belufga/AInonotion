class_name ExplosiveBarrel
extends RigidBody3D
## Fuel barrel: thin steel walls, a HealthComponent, and an Explosion when it runs out.
## A short random delay after the fatal hit staggers chain reactions between neighbours.

@export var tnt_equivalent := 0.9
@export var shrapnel_count := 48
@export var gib_radius := 2.2

var health: HealthComponent

var _fuse := -1.0
var _attacker: Node


static func create() -> ExplosiveBarrel:
	var barrel := ExplosiveBarrel.new()
	barrel.name = "ExplosiveBarrel"
	barrel.mass = 45.0
	barrel.collision_layer = Layers.PROPS
	barrel.collision_mask = Layers.WORLD | Layers.PROPS | Layers.BODY | Layers.PLAYER | Layers.PROJECTILES
	barrel.set_meta(BallisticMaterial.META_SURFACE, &"metal")
	barrel.set_meta(BallisticMaterial.META_WALL, 0.0015)
	barrel.add_to_group(Layers.GROUP_ENTITY)

	var shape := CylinderShape3D.new()
	shape.radius = 0.29
	shape.height = 0.88
	var collider := CollisionShape3D.new()
	collider.shape = shape
	barrel.add_child(collider)

	var drum := CylinderMesh.new()
	drum.top_radius = 0.29
	drum.bottom_radius = 0.29
	drum.height = 0.88
	drum.radial_segments = 20
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.72, 0.1, 0.08)
	paint.metallic = 0.5
	paint.roughness = 0.5
	var body := MeshInstance3D.new()
	body.mesh = drum
	body.material_override = paint
	barrel.add_child(body)
	var band_mesh := CylinderMesh.new()
	band_mesh.top_radius = 0.296
	band_mesh.bottom_radius = 0.296
	band_mesh.height = 0.16
	band_mesh.radial_segments = 20
	var hazard := StandardMaterial3D.new()
	hazard.albedo_color = Color(0.95, 0.78, 0.1)
	hazard.roughness = 0.6
	var band := MeshInstance3D.new()
	band.mesh = band_mesh
	band.material_override = hazard
	barrel.add_child(band)

	barrel.health = HealthComponent.new()
	barrel.health.name = "HealthComponent"
	barrel.health.max_health = 60.0
	barrel.health.joules_per_hp = 18.0
	barrel.health.kpa_per_hp = 0.9
	barrel.add_child(barrel.health)
	barrel.health.died.connect(barrel._on_died)
	return barrel


func _physics_process(delta: float) -> void:
	if _fuse < 0.0:
		return
	_fuse -= delta
	if _fuse <= 0.0:
		_fuse = -1.0
		Explosion.detonate(self, global_position, tnt_equivalent, shrapnel_count, gib_radius,
			_attacker if is_instance_valid(_attacker) else null)
		queue_free()


func _on_died(info: DamageInfo) -> void:
	_attacker = info.attacker if info != null else null
	_fuse = randf_range(0.05, 0.25)
