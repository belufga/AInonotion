class_name Layers
extends RefCounted
## Physics and render layer masks shared by every system.

const WORLD := 1 << 0        ## Static level geometry.
const PROPS := 1 << 1        ## Dynamic rigid bodies, vehicles, breakables.
const PLAYER := 1 << 2
const BODY := 1 << 3         ## Ragdoll PhysicalBone3D: the skin layer of the hitbox model.
const ORGANS := 1 << 4       ## OrganVolume3D areas; only ballistic queries touch them.
const GIBS := 1 << 5
const PROJECTILES := 1 << 6  ## Thrown grenades.

const SOLID := WORLD | PROPS
const BALLISTIC := WORLD | PROPS | BODY
const TOOL := WORLD | PROPS | BODY | GIBS | PROJECTILES

const VIS_WORLD := 1 << 0
const VIS_VIEWMODEL := 1 << 1

const GROUP_ENTITY := &"sandbox_entity"
const GROUP_ENTITY_CONTAINER := &"entity_container"


## Walks up from a collider to the spawnable entity that owns it.
static func entity_root(node: Node) -> Node:
	var n := node
	while n != null:
		if n.is_in_group(GROUP_ENTITY):
			return n
		n = n.get_parent()
	return null


## Seconds of simulated physics time; unlike wall-clock time it follows slow motion and fixed-fps runs.
static func physics_time() -> float:
	return Engine.get_physics_frames() / float(Engine.physics_ticks_per_second)
