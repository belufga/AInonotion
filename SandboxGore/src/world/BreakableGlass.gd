class_name BreakableGlass
extends StaticBody3D
## Window pane. Any bullet or a few kilopascals of blast overpressure shatters it into shards.

const SHARD_COUNT := 14
const SHARD_LIFE := 6.0

var size := Vector3(1.6, 1.2, 0.012)
var health: HealthComponent

static var _material: StandardMaterial3D


static func create(p_size := Vector3(1.6, 1.2, 0.012)) -> BreakableGlass:
	var pane := BreakableGlass.new()
	pane.name = "GlassPane"
	pane.size = p_size
	pane.collision_layer = Layers.PROPS
	pane.collision_mask = 0
	pane.set_meta(BallisticMaterial.META_SURFACE, &"glass")
	pane.add_to_group(Layers.GROUP_ENTITY)
	var shape := BoxShape3D.new()
	shape.size = p_size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	pane.add_child(collider)
	var mesh := BoxMesh.new()
	mesh.size = p_size
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = _glass_material()
	pane.add_child(visual)
	pane.health = HealthComponent.new()
	pane.health.name = "HealthComponent"
	pane.health.max_health = 6.0
	pane.health.joules_per_hp = 3.0
	pane.health.kpa_per_hp = 1.0  # Ordinary windows fail at roughly 5 kPa.
	pane.add_child(pane.health)
	pane.health.died.connect(pane._shatter)
	return pane


func _shatter(info: DamageInfo) -> void:
	var push := info.direction * 2.5 if info != null else Vector3.ZERO
	Sfx.play(&"glass", global_position)
	BloodFX.debris_particles.emit(global_position, push if push != Vector3.ZERO else Vector3.UP, 1.0, 5.0, 70.0, 1.0, Color(0.85, 0.95, 1.0))
	var scene := get_tree().current_scene
	for i in SHARD_COUNT:
		var shard_size := Vector3(randf_range(0.08, 0.25), randf_range(0.08, 0.25), size.z)
		var shard := RigidBody3D.new()
		shard.mass = 0.08
		shard.collision_layer = Layers.GIBS
		shard.collision_mask = Layers.SOLID
		var shape := BoxShape3D.new()
		shape.size = shard_size
		var collider := CollisionShape3D.new()
		collider.shape = shape
		shard.add_child(collider)
		var mesh := BoxMesh.new()
		mesh.size = shard_size
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.material_override = _glass_material()
		shard.add_child(visual)
		scene.add_child(shard)
		var offset := Vector3(randf_range(-0.5, 0.5) * size.x, randf_range(-0.5, 0.5) * size.y, 0.0)
		shard.global_transform = Transform3D(global_basis, global_transform * offset)
		shard.linear_velocity = push * randf_range(0.3, 1.0) + Vector3(randf() - 0.5, randf() * 0.5, randf() - 0.5) * 2.0
		shard.angular_velocity = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 12.0
		scene.get_tree().create_timer(SHARD_LIFE + randf()).timeout.connect(shard.queue_free)
	queue_free()


static func _glass_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.albedo_color = Color(0.7, 0.88, 0.95, 0.3)
		_material.roughness = 0.05
		_material.metallic = 0.2
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _material
