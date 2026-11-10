class_name ParticleRingPool
extends Node3D
## Ring buffer of one-shot GPUParticles3D emitters. Each emitter owns its process material so
## a burst can be re-aimed without disturbing particles another emitter still has in flight.

var capacity := 32

var _mesh: Mesh
var _amount := 32
var _lifetime := 1.0
var _scale := Vector2(0.6, 1.6)
var _gravity := Vector3(0.0, -9.8, 0.0)
var _emitters: Array[GPUParticles3D] = []
var _materials: Array[ParticleProcessMaterial] = []
var _head := 0


func _init(p_capacity: int, mesh: Mesh, amount: int, lifetime: float, scale_range := Vector2(0.6, 1.6),
		gravity := Vector3(0.0, -9.8, 0.0)) -> void:
	capacity = p_capacity
	_mesh = mesh
	_amount = amount
	_lifetime = lifetime
	_scale = scale_range
	_gravity = gravity


func _ready() -> void:
	for i in capacity:
		var material := ParticleProcessMaterial.new()
		material.gravity = _gravity
		material.scale_min = _scale.x
		material.scale_max = _scale.y
		material.lifetime_randomness = 0.4
		# Needs a GPUParticlesCollision3D in the level; without one the particles simply fall through.
		material.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
		var emitter := GPUParticles3D.new()
		emitter.one_shot = true
		emitter.emitting = false
		emitter.explosiveness = 0.9
		emitter.amount = _amount
		emitter.lifetime = _lifetime
		emitter.local_coords = false
		emitter.draw_pass_1 = _mesh
		emitter.process_material = material
		emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		emitter.visibility_aabb = AABB(Vector3(-8.0, -8.0, -8.0), Vector3(16.0, 16.0, 16.0))
		emitter.layers = Layers.VIS_WORLD
		add_child(emitter)
		_emitters.append(emitter)
		_materials.append(material)


## Fires the oldest emitter. `amount_ratio` scales the particle count without reallocating.
func emit(position: Vector3, direction: Vector3, speed_min: float, speed_max: float, spread_degrees: float,
		amount_ratio := 1.0, color := Color.WHITE) -> void:
	var material := _materials[_head]
	var emitter := _emitters[_head]
	_head = (_head + 1) % capacity
	material.direction = direction.normalized()
	material.spread = spread_degrees
	material.initial_velocity_min = speed_min
	material.initial_velocity_max = speed_max
	material.color = color
	emitter.global_position = position
	emitter.amount_ratio = clampf(amount_ratio, 0.05, 1.0)
	emitter.restart()
