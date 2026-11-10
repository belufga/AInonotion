class_name WeaponPickup
extends RigidBody3D
## A weapon lying in the world as a physics prop: spawned from the toolgun or dropped by an NPC.
## The player collects it with the interact key to refill ammunition for that weapon.

var weapon_id: StringName = &"ak47"


static func create(id: StringName) -> WeaponPickup:
	var pickup := WeaponPickup.new()
	pickup.weapon_id = id
	pickup.name = "Pickup_" + String(id)
	pickup.mass = 0.4 if id == &"grenade" else 3.2
	pickup.collision_layer = Layers.PROPS
	pickup.collision_mask = Layers.WORLD | Layers.PROPS | Layers.BODY | Layers.PLAYER
	pickup.set_meta(BallisticMaterial.META_SURFACE, &"metal")
	pickup.add_to_group(Layers.GROUP_ENTITY)
	var size := WeaponModels.bounds(id)
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	# Models are built around the grip, so centre the box on the weapon's body.
	collider.position = Vector3(0.0, -0.02, -size.z * 0.5 + 0.3) if size.z > 0.5 else Vector3(0.0, -0.02, -0.04)
	pickup.add_child(collider)
	pickup.add_child(WeaponModels.build(id, false))
	return pickup
