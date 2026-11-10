class_name SpawnCatalog
extends RefCounted
## Everything the toolgun can spawn. `height` is how far above the aimed surface the entity's
## origin has to sit so it rests on it.

const ITEMS: Array[Dictionary] = [
	{"id": &"civilian", "label": "Civilian", "color": Color(0.85, 0.65, 0.5), "height": 0.02},
	{"id": &"soldier", "label": "Armed NPC", "color": Color(0.35, 0.5, 0.3), "height": 0.02},
	{"id": &"barrel", "label": "Explosive Barrel", "color": Color(0.8, 0.15, 0.1), "height": 0.46},
	{"id": &"crate", "label": "Wood Crate", "color": Color(0.6, 0.42, 0.22), "height": 0.42},
	{"id": &"steel_plate", "label": "Steel Plate", "color": Color(0.5, 0.52, 0.56), "height": 0.77},
	{"id": &"glass", "label": "Glass Pane", "color": Color(0.6, 0.85, 0.95), "height": 0.62},
	{"id": &"concrete", "label": "Concrete Block", "color": Color(0.62, 0.6, 0.57), "height": 0.27},
	{"id": &"vehicle", "label": "Vehicle", "color": Color(0.2, 0.35, 0.6), "height": 0.3},
	{"id": &"ak47", "label": "AK-47", "color": Color(0.45, 0.25, 0.12), "height": 0.3},
	{"id": &"pistol", "label": "Pistol", "color": Color(0.3, 0.3, 0.33), "height": 0.3},
	{"id": &"shotgun", "label": "Shotgun", "color": Color(0.36, 0.2, 0.1), "height": 0.3},
	{"id": &"live_grenade", "label": "Live Grenade", "color": Color(0.3, 0.38, 0.18), "height": 0.1},
]


static func find(id: StringName) -> Dictionary:
	for item in ITEMS:
		if item.id == id:
			return item
	return ITEMS[0]


## Creates `id` resting on `position` (a point on a surface), turned to `yaw`, under `container`.
static func spawn(id: StringName, position: Vector3, yaw: float, container: Node) -> Node3D:
	var entity := _create(id)
	if entity == null:
		return null
	# Ragdolls are built where they enter the tree, so the transform has to be set first.
	entity.position = position + Vector3.UP * float(find(id).height)
	entity.rotation.y = yaw
	container.add_child(entity)
	if entity is GrenadeProjectile:
		entity.release_spoon()
	return entity


## The node new entities should be parented to.
static func container(tree: SceneTree) -> Node:
	var node := tree.get_first_node_in_group(Layers.GROUP_ENTITY_CONTAINER)
	return node if node != null else tree.current_scene


static func _create(id: StringName) -> Node3D:
	match id:
		&"civilian", &"soldier":
			var npc := Humanoid.new()
			npc.armed = id == &"soldier"
			npc.name = "Soldier" if npc.armed else "Civilian"
			return npc
		&"barrel":
			return ExplosiveBarrel.create()
		&"crate":
			return PropFactory.crate()
		&"steel_plate":
			return PropFactory.steel_plate()
		&"glass":
			return BreakableGlass.create()
		&"concrete":
			return PropFactory.concrete_block()
		&"vehicle":
			return PropFactory.vehicle()
		&"ak47", &"pistol", &"shotgun":
			return WeaponPickup.create(id)
		&"live_grenade":
			return GrenadeProjectile.create()
	return null
