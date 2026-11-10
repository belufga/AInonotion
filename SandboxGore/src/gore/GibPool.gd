class_name GibPool
extends Node3D
## Ring buffer of Gib rigid bodies. The oldest giblet is recycled when the pool is exhausted.

var capacity := 96

var _gibs: Array[Gib] = []
var _head := 0
var _meat: SphereMesh
var _organ: SphereMesh
var _bone: BoxMesh


func _ready() -> void:
	_meat = _blob(Color(0.42, 0.04, 0.04), 0.3)
	_organ = _blob(Color(0.33, 0.05, 0.12), 0.2)
	_bone = BoxMesh.new()
	var bone_material := StandardMaterial3D.new()
	bone_material.albedo_color = Color(0.88, 0.8, 0.7)
	bone_material.roughness = 0.6
	_bone.material = bone_material
	for i in capacity:
		var gib := Gib.new()
		add_child(gib)
		_gibs.append(gib)


func spawn(kind: Gib.Kind, origin: Vector3, velocity: Vector3) -> void:
	var gib := _gibs[_head]
	_head = (_head + 1) % capacity
	match kind:
		Gib.Kind.BONE:
			gib.launch(kind, _bone, Vector3(randf_range(0.02, 0.03), randf_range(0.02, 0.03), randf_range(0.08, 0.16)), origin, velocity)
		Gib.Kind.ORGAN:
			var s := randf_range(0.07, 0.1)
			gib.launch(kind, _organ, Vector3(s, s * 0.8, s), origin, velocity)
		_:
			gib.launch(kind, _meat, Vector3(randf_range(0.06, 0.12), randf_range(0.04, 0.07), randf_range(0.05, 0.1)), origin, velocity)


## Throws `count` mixed giblets in a cone around `direction`.
func burst(origin: Vector3, direction: Vector3, count: int, speed: float, spread := 0.6, bone_ratio := 0.25) -> void:
	var dir := direction.normalized()
	for i in count:
		var scatter := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 2.0 * spread
		var roll := randf()
		var kind := Gib.Kind.BONE if roll < bone_ratio else (Gib.Kind.ORGAN if roll > 0.85 else Gib.Kind.MEAT)
		spawn(kind, origin + scatter * 0.08, (dir + scatter).normalized() * speed * randf_range(0.5, 1.0))


func active_count() -> int:
	var count := 0
	for gib in _gibs:
		if gib.active:
			count += 1
	return count


func clear() -> void:
	for gib in _gibs:
		gib.retire()


func _blob(color: Color, roughness: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	mesh.material = material
	return mesh
