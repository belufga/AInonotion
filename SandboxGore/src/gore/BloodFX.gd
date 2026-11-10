extends Node3D
## Blood Decal Spawner (autoload "BloodFX").
##
## Owns every pooled gore resource: the decal ring buffer, blood and debris particle rings and
## the gib pool. Gameplay code calls the intent-level methods below and never creates decals,
## emitters or giblets itself.

const DECAL_CAPACITY := 320
const DECAL_DEPTH := 0.3
const POOL_DEPTH := 0.2
const MAX_POOL_RADIUS := 1.0
const POOL_GROWTH_SPEED := 0.09  ## m/s of radius.
const SPURTS_PER_SECOND := 30.0  ## Global budget so a massacre cannot starve the emitter ring.

var decals: DecalRingPool
var blood_particles: ParticleRingPool
var debris_particles: ParticleRingPool
var gibs: GibPool

var _splats: Array[ImageTexture] = []
var _sprays: Array[ImageTexture] = []
var _pool_textures: Array[ImageTexture] = []
var _smears: Array[ImageTexture] = []
var _wounds: Array[ImageTexture] = []
var _hole: ImageTexture
var _scorch: ImageTexture
var _rng := RandomNumberGenerator.new()
var _pools: Dictionary = {}  ## source id -> {index, generation, position, volume, radius, target, fed}
var _spurt_budget := 8.0


func _ready() -> void:
	_rng.randomize()
	for i in 4:
		_splats.append(BloodTextures.splat(_rng))
	for i in 2:
		_sprays.append(BloodTextures.spray(_rng))
		_pool_textures.append(BloodTextures.pool(_rng))
		_smears.append(BloodTextures.smear(_rng))
		_wounds.append(BloodTextures.wound(_rng))
	_hole = BloodTextures.bullet_hole(_rng)
	_scorch = BloodTextures.scorch(_rng)

	decals = DecalRingPool.new(DECAL_CAPACITY)
	decals.name = "Decals"
	add_child(decals)

	var droplet := SphereMesh.new()
	droplet.radius = 0.012
	droplet.height = 0.024
	droplet.radial_segments = 6
	droplet.rings = 3
	var blood := StandardMaterial3D.new()
	blood.albedo_color = Color(0.4, 0.0, 0.0)
	blood.roughness = 0.25
	droplet.material = blood
	blood_particles = ParticleRingPool.new(40, droplet, 40, 0.9)
	blood_particles.name = "BloodParticles"
	add_child(blood_particles)

	var chip := BoxMesh.new()
	chip.size = Vector3(0.022, 0.022, 0.022)
	var chip_material := StandardMaterial3D.new()
	chip_material.vertex_color_use_as_albedo = true
	chip.material = chip_material
	debris_particles = ParticleRingPool.new(16, chip, 24, 0.7)
	debris_particles.name = "DebrisParticles"
	add_child(debris_particles)

	gibs = GibPool.new()
	gibs.name = "Gibs"
	add_child(gibs)


func _process(delta: float) -> void:
	_spurt_budget = minf(_spurt_budget + SPURTS_PER_SECOND * delta, 8.0)
	if _pools.is_empty():
		return
	var now := Layers.physics_time()
	for key in _pools.keys():
		var pool: Dictionary = _pools[key]
		if not decals.is_current(pool.index, pool.generation):
			_pools.erase(key)
		elif pool.radius < pool.target:
			pool.radius = move_toward(pool.radius, pool.target, POOL_GROWTH_SPEED * delta)
			decals.get_decal(pool.index).size = Vector3(pool.radius * 2.0, POOL_DEPTH, pool.radius * 2.0)
		elif now - pool.fed > 30.0:
			_pools.erase(key)  # Finished growing; the decal stays, only the bookkeeping goes.


## Stain on a surface. With a `travel` direction it becomes an elongated directional spatter.
func blood_splat(position: Vector3, normal: Vector3, size: float, parent: Node3D = null, travel := Vector3.ZERO) -> void:
	var directional := travel.length_squared() > 0.01 and absf(travel.normalized().dot(normal)) < 0.85
	if directional:
		var xform := DecalRingPool.surface_transform(position, normal, travel)
		var length := size * 1.7
		xform.origin -= xform.basis.z * length * 0.35  # The texture's source edge sits on the impact point.
		decals.place(_pick(_sprays), xform, Vector3(size, DECAL_DEPTH, length), Color.WHITE, parent)
	else:
		var xform := DecalRingPool.surface_transform(position, normal, Vector3.ZERO, _rng.randf() * TAU)
		decals.place(_pick(_splats), xform, Vector3(size, DECAL_DEPTH, size), Color.WHITE, parent)


func blood_burst(position: Vector3, direction: Vector3, speed: float, amount_ratio := 0.5, spread := 22.0) -> void:
	blood_particles.emit(position, direction, speed * 0.4, speed, spread, amount_ratio)


## Pulsed jet from an arterial wound, called once per heartbeat. Exit speed follows
## Torricelli's law, v = sqrt(2 * dP / rho), so the jet weakens as blood pressure falls.
func arterial_spurt(position: Vector3, direction: Vector3, systolic_mmhg: float) -> void:
	if _spurt_budget < 1.0:
		return
	_spurt_budget -= 1.0
	var speed := sqrt(2.0 * systolic_mmhg * 133.3 / 1060.0)
	var strength := clampf(systolic_mmhg / 120.0, 0.2, 1.0)
	blood_particles.emit(position, direction, speed * 0.7, speed, 7.0, strength)
	_land_droplet(position, direction.normalized() * speed * _rng.randf_range(0.75, 1.0), 0.12 + 0.12 * strength)


## Throws blood from an exit wound onto whatever is behind the victim.
func project_splatter(origin: Vector3, direction: Vector3, max_distance: float, size: float) -> void:
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * max_distance, Layers.SOLID)
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		_land_droplet(origin, direction * 6.0, size * 0.7)
		return
	var falloff := 1.0 - 0.5 * origin.distance_to(result.position) / max_distance
	blood_splat(result.position, result.normal, size * falloff, _moving_parent(result.collider), direction)


## Throws a blob of blood on a ballistic arc and stains wherever it lands.
func fling(origin: Vector3, velocity: Vector3, size: float) -> void:
	_land_droplet(origin, velocity, size)


## Entry or exit wound drawn on the body itself; the decal rides the bone.
func wound_mark(bone: Node3D, position: Vector3, normal: Vector3, size: float) -> void:
	var xform := DecalRingPool.surface_transform(position, normal, Vector3.ZERO, _rng.randf() * TAU)
	decals.place(_pick(_wounds), xform, Vector3(size, 0.07, size), Color.WHITE, bone)


## Feeds `ml` of blood to the floor under `position`. Blood from one source keeps feeding the
## same pool, whose radius grows with the square root of its volume, until the source moves away.
func drip(source_id: int, position: Vector3, ml: float) -> void:
	var query := PhysicsRayQueryParameters3D.create(position, position + Vector3.DOWN * 2.5, Layers.WORLD)
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty() or result.normal.y < 0.6:
		return
	var now := Layers.physics_time()
	if _pools.has(source_id):
		var pool: Dictionary = _pools[source_id]
		if decals.is_current(pool.index, pool.generation) and pool.position.distance_to(result.position) < pool.radius + 0.25:
			pool.volume += ml
			pool.target = minf(_pool_radius(pool.volume), MAX_POOL_RADIUS)
			pool.fed = now
			return
	var xform := DecalRingPool.surface_transform(result.position, result.normal, Vector3.ZERO, _rng.randf() * TAU)
	var index := decals.place(_pick(_pool_textures), xform, Vector3(0.1, POOL_DEPTH, 0.1))
	_pools[source_id] = {
		"index": index, "generation": decals.generations[index], "position": result.position,
		"volume": ml, "radius": 0.05, "target": minf(_pool_radius(ml), MAX_POOL_RADIUS), "fed": now,
	}


## Stain left by a giblet touching down; a streak if it is still sliding.
func gib_stain(position: Vector3, velocity: Vector3) -> void:
	var query := PhysicsRayQueryParameters3D.create(position, position + Vector3.DOWN * 0.3, Layers.SOLID)
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return
	var slide := Vector3(velocity.x, 0.0, velocity.z)
	if slide.length() > 1.5:
		var xform := DecalRingPool.surface_transform(result.position, result.normal, slide)
		decals.place(_pick(_smears), xform, Vector3(0.14, DECAL_DEPTH, 0.4), Color.WHITE, _moving_parent(result.collider))
	else:
		blood_splat(result.position, result.normal, _rng.randf_range(0.12, 0.22), _moving_parent(result.collider))


## Bullet hole and debris puff on a non-flesh surface.
func surface_impact(position: Vector3, normal: Vector3, material: BallisticMaterial, energy: float, collider: Object) -> void:
	var strength := clampf(energy / 1500.0, 0.15, 1.0)
	debris_particles.emit(position + normal * 0.02, normal, 1.5, 3.0 + 5.0 * strength, 35.0, strength, material.debris_color)
	if material.leaves_hole:
		var size := 0.05 + 0.07 * strength
		var xform := DecalRingPool.surface_transform(position, normal, Vector3.ZERO, _rng.randf() * TAU)
		decals.place(_hole, xform, Vector3(size, 0.1, size), Color.WHITE, _moving_parent(collider))


func scorch(position: Vector3, normal: Vector3, radius: float) -> void:
	var xform := DecalRingPool.surface_transform(position, normal, Vector3.ZERO, _rng.randf() * TAU)
	decals.place(_scorch, xform, Vector3(radius * 2.0, 0.5, radius * 2.0))


func stats() -> Dictionary:
	return {"decals": decals.used_count(), "decal_capacity": decals.capacity, "pools": _pools.size(), "gibs": gibs.active_count()}


func clear() -> void:
	decals.clear()
	gibs.clear()
	_pools.clear()


## Follows a droplet's ballistic arc with short ray segments and stains the first surface it meets.
func _land_droplet(origin: Vector3, velocity: Vector3, size: float) -> void:
	var space := get_world_3d().direct_space_state
	var p := origin
	var v := velocity
	var step := 0.07
	for i in 12:
		var next := p + v * step + Vector3.DOWN * 4.9 * step * step
		var result := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, next, Layers.SOLID))
		if not result.is_empty():
			blood_splat(result.position, result.normal, size, _moving_parent(result.collider), v)
			return
		p = next
		v += Vector3.DOWN * 9.8 * step


func _pool_radius(ml: float) -> float:
	return 0.02 * sqrt(ml)


func _pick(textures: Array[ImageTexture]) -> ImageTexture:
	return textures[_rng.randi() % textures.size()]


## Decals on dynamic bodies must be parented to them or they would stay behind in mid-air.
func _moving_parent(collider: Object) -> Node3D:
	if collider is RigidBody3D or collider is PhysicalBone3D:
		return collider
	return null
