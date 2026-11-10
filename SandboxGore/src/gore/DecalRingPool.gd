class_name DecalRingPool
extends Node3D
## Fixed-size ring buffer of Decal nodes.
##
## Placing a decal never allocates: the oldest one is re-skinned and moved. Node count, memory
## and clustered-decal cost therefore stay flat however long a session runs, and there is no
## garbage for the engine to collect in the middle of a firefight.

var capacity := 256
## Bumped every time a slot is reused; callers keep (index, generation) to detect recycling.
var generations := PackedInt32Array()

var _decals: Array[Decal] = []
var _head := 0
var _used := 0


func _init(p_capacity := 256) -> void:
	capacity = p_capacity


func _ready() -> void:
	generations.resize(capacity)
	generations.fill(0)
	for i in capacity:
		_decals.append(_create())


## Builds a decal transform lying on a surface: local +Y along the normal, local -Z along
## `forward` projected onto the surface (or a rolled arbitrary axis when no direction is given).
static func surface_transform(position: Vector3, normal: Vector3, forward := Vector3.ZERO, roll := 0.0) -> Transform3D:
	var y := normal.normalized()
	var reference := forward
	if reference.length_squared() < 1e-6 or absf(reference.normalized().dot(y)) > 0.98:
		reference = Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.FORWARD
	var z := -(reference - y * reference.dot(y)).normalized()
	var basis := Basis(y.cross(z), y, z)
	if roll != 0.0:
		basis = basis.rotated(y, roll)
	return Transform3D(basis, position)


## Places the oldest decal and returns its slot index. `parent` makes it ride a moving body.
func place(texture: Texture2D, xform: Transform3D, size: Vector3, tint := Color.WHITE, parent: Node3D = null) -> int:
	var index := _head
	_head = (_head + 1) % capacity
	_used = mini(_used + 1, capacity)
	generations[index] += 1
	var decal := _decals[index]
	if not is_instance_valid(decal):
		# The body this decal was riding on has been deleted.
		decal = _create()
		_decals[index] = decal
	var target: Node3D = parent if parent != null and is_instance_valid(parent) else self
	if decal.get_parent() != target:
		decal.get_parent().remove_child(decal)
		target.add_child(decal)
	decal.texture_albedo = texture
	decal.size = size
	decal.modulate = tint
	decal.global_transform = xform
	decal.visible = true
	return index


func get_decal(index: int) -> Decal:
	var decal := _decals[index]
	return decal if is_instance_valid(decal) else null


func is_current(index: int, generation: int) -> bool:
	return generations[index] == generation and is_instance_valid(_decals[index])


func used_count() -> int:
	return _used


func clear() -> void:
	for i in capacity:
		var decal := _decals[i]
		if is_instance_valid(decal):
			decal.visible = false
		generations[i] += 1
	_used = 0


func _create() -> Decal:
	var decal := Decal.new()
	decal.visible = false
	decal.cull_mask = Layers.VIS_WORLD
	decal.upper_fade = 0.15
	decal.lower_fade = 0.15
	decal.normal_fade = 0.3
	decal.distance_fade_enabled = true
	decal.distance_fade_begin = 45.0
	decal.distance_fade_length = 15.0
	add_child(decal)
	return decal
