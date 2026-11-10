class_name GrenadeProjectile
extends RigidBody3D
## The thrown grenade: a bouncing rigid body with a burning fuse. Detonation is handed to
## Explosion (shockwave, shrapnel, epicentre gibbing).

@export var tnt_equivalent := 0.23  ## kg; an M67 carries 180 g of Composition B.
@export var shrapnel_count := 96
@export var gib_radius := 1.3

var fuse_left := -1.0  ## Negative while the spoon is still on.
var attacker: Node
var exploded := false


static func create(p_attacker: Node = null) -> GrenadeProjectile:
	var grenade := GrenadeProjectile.new()
	grenade.name = "Grenade"
	grenade.attacker = p_attacker
	grenade.mass = 0.4
	grenade.continuous_cd = true
	grenade.collision_layer = Layers.PROJECTILES
	grenade.collision_mask = Layers.WORLD | Layers.PROPS | Layers.BODY
	grenade.add_to_group(Layers.GROUP_ENTITY)
	var material := PhysicsMaterial.new()
	material.bounce = 0.35
	material.friction = 0.8
	grenade.physics_material_override = material
	grenade.angular_damp = 1.5
	var shape := SphereShape3D.new()
	shape.radius = 0.035
	var collider := CollisionShape3D.new()
	collider.shape = shape
	grenade.add_child(collider)
	var visual := WeaponModels.grenade(false)
	visual.get_node(^"Pin").visible = false
	grenade.add_child(visual)
	return grenade


## Starts the fuse. An M67 burns for 3.5 to 4 seconds once the safety lever is released.
func release_spoon(fuse_seconds := -1.0) -> void:
	fuse_left = fuse_seconds if fuse_seconds > 0.0 else randf_range(3.5, 4.0)
	var spoon := get_node_or_null(^"Grenade/Spoon") as Node3D
	if spoon != null:
		spoon.visible = false


func _physics_process(delta: float) -> void:
	if fuse_left < 0.0 or exploded:
		return
	fuse_left -= delta
	if fuse_left <= 0.0:
		explode()


func explode() -> void:
	if exploded:
		return
	exploded = true
	# Raised slightly so a grenade lying on the floor does not waste its fragments in it.
	Explosion.detonate(self, global_position + Vector3.UP * 0.08, tnt_equivalent, shrapnel_count, gib_radius,
		attacker if is_instance_valid(attacker) else null)
	queue_free()
