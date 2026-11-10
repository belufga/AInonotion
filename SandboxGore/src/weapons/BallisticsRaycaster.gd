class_name BallisticsRaycaster
extends RefCounted
## Penetrating ray tracer shared by every projectile source (bullets, pellets, shrapnel).
##
## A shot is followed surface by surface. Each solid it meets is measured with a reverse ray to
## find the exit point, the material model removes kinetic energy for that thickness, and the
## shot continues from the far side with what is left. Body parts are delegated to
## HitboxComponent, which resolves the anatomical layers inside them.

const MAX_SURFACES := 12
const BODY_MAX_CHORD := 0.7   ## Longest path through a single body part.
const MAX_PROP_DEPTH := 2.5   ## Longest path searched through a prop.


## Advances `shot` by up to `max_distance` metres, applying air drag and every penetration on
## the way. On return `shot.position` is where it stopped or how far it got.
static func trace(space: PhysicsDirectSpaceState3D, shot: BallisticShot, max_distance: float) -> void:
	var remaining := max_distance
	var drag := shot.caliber.air_drag_k()
	for i in MAX_SURFACES:
		if remaining <= 0.0 or not shot.alive:
			return
		var from := shot.position
		var query := PhysicsRayQueryParameters3D.create(from, from + shot.direction * remaining, Layers.BALLISTIC)
		var result := space.intersect_ray(query)
		if result.is_empty():
			_fly(shot, remaining, drag)
			return
		var entry: Vector3 = result.position
		var travelled := from.distance_to(entry)
		_fly(shot, travelled, drag)
		shot.position = entry
		remaining -= travelled

		var collider: Object = result.collider
		var energy_in := shot.energy
		var hitbox := HitboxComponent.of(collider)
		var exit_point: Variant
		if hitbox != null:
			exit_point = find_exit(space, collider, entry, shot.direction, BODY_MAX_CHORD)
			hitbox.resolve_ballistic(space, shot, entry, exit_point, result.normal)
		else:
			exit_point = _penetrate_surface(space, shot, collider, entry, result.normal)
		if shot.record:
			shot.hits.append({
				"collider": collider, "position": entry, "energy_in": energy_in, "energy_out": shot.energy,
				"part": hitbox.part if hitbox != null else &"", "surface": BallisticMaterial.of(collider).id,
			})
		if not shot.alive or exit_point == null:
			shot.alive = false
			return
		var exit_position: Vector3 = exit_point
		var thickness := entry.distance_to(exit_position)
		remaining -= thickness
		shot.distance += thickness
		# Passing through a solid knocks the projectile slightly off its line.
		var lost := 1.0 - shot.energy / maxf(energy_in, 0.001)
		var wobble := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.06 * lost
		shot.direction = (shot.direction + wobble).normalized()
		shot.position = exit_position + shot.direction * 0.004
	shot.alive = false


## Finds where a ray entering `collider` at `entry` leaves it again, by casting back from
## `max_depth` further along. Returns null when the solid is thicker than `max_depth`.
static func find_exit(space: PhysicsDirectSpaceState3D, collider: Object, entry: Vector3, direction: Vector3, max_depth: float) -> Variant:
	var query := PhysicsRayQueryParameters3D.create(entry + direction * max_depth, entry + direction * 0.001, Layers.BALLISTIC)
	var exclude: Array[RID] = []
	for i in 8:
		query.exclude = exclude
		var result := space.intersect_ray(query)
		if result.is_empty():
			return null
		if result.collider == collider:
			return result.position
		exclude.append(result.rid)  # Something else lies beyond the target; look past it.
	return null


static func _fly(shot: BallisticShot, distance: float, drag: float) -> void:
	shot.position += shot.direction * distance
	shot.speed *= exp(-drag * distance)
	shot.distance += distance


## World geometry and props. Returns the exit point, or null if the projectile stopped inside.
static func _penetrate_surface(space: PhysicsDirectSpaceState3D, shot: BallisticShot, collider: Object, entry: Vector3, normal: Vector3) -> Variant:
	var material := BallisticMaterial.of(collider)
	var cal := shot.caliber
	var energy_in := shot.energy
	var speed_in := shot.speed
	var wall: float = collider.get_meta(BallisticMaterial.META_WALL, 0.0)
	var exit_point: Variant = null
	var thickness := INF
	if wall > 0.0:
		# Hollow prop: only its two walls resist, however far apart they are.
		exit_point = find_exit(space, collider, entry, shot.direction, MAX_PROP_DEPTH)
		if exit_point != null:
			thickness = wall * 2.0
	else:
		var reach := minf(material.stop_depth(cal, energy_in) + 0.02, MAX_PROP_DEPTH)
		exit_point = find_exit(space, collider, entry, shot.direction, reach)
		if exit_point != null:
			thickness = entry.distance_to(exit_point)

	var energy_out := 0.0
	if exit_point != null:
		energy_out = material.energy_after(cal, energy_in, thickness)
	if energy_out < HitboxComponent.MIN_ENERGY:
		energy_out = 0.0
		exit_point = null
	shot.energy = energy_out
	shot.alive = exit_point != null
	var deposited := energy_in - energy_out

	var info := DamageInfo.make(shot.damage_type, entry, shot.direction, shot.live_attacker())
	info.energy = deposited
	info.normal = normal
	info.caliber = cal
	var health := HealthComponent.of(collider)
	if health != null:
		health.apply_damage(info)
	var body := collider as RigidBody3D
	if body != null and not body.freeze:
		body.apply_impulse(shot.direction * cal.mass * (speed_in - shot.speed) * cal.impulse_scale, entry - body.global_position)
	BloodFX.surface_impact(entry, normal, material, deposited, collider)
	if exit_point != null:
		BloodFX.surface_impact(exit_point, shot.direction, material, energy_out * 0.3, collider)
	return exit_point
