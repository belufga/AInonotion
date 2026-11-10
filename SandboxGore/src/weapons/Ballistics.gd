extends Node3D
## Hybrid ballistics service (autoload "Ballistics").
##
## A fired shot is resolved instantly by raycast out to the weapon's hitscan range. If it is
## still flying after that, it becomes a simulated projectile: every physics tick it is pulled
## down by gravity, slowed by quadratic air drag and swept along its path with the same
## penetrating tracer, so distant shots drop, lose energy and can still punch through cover.

const MAX_FLIGHT_TIME := 4.0
const MIN_SPEED := 50.0
const TRACER_COUNT := 32
const TRACER_LIFE := 0.06

var _flying: Array[BallisticShot] = []
var _tracers: Array[MeshInstance3D] = []
var _tracer_materials: Array[StandardMaterial3D] = []
var _tracer_age := PackedFloat32Array()
var _tracer_head := 0


func _ready() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.012, 0.012, 1.0)
	for i in TRACER_COUNT:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		var tracer := MeshInstance3D.new()
		tracer.mesh = mesh
		tracer.material_override = material
		tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tracer.visible = false
		add_child(tracer)
		_tracers.append(tracer)
		_tracer_materials.append(material)
		_tracer_age.append(TRACER_LIFE)


## Fires `shot`. `visual_origin` is where the tracer should appear to start (the muzzle).
func fire(shot: BallisticShot, hitscan_range: float, visual_origin := Vector3.INF) -> void:
	var start := shot.position
	BallisticsRaycaster.trace(get_world_3d().direct_space_state, shot, hitscan_range)
	_show_tracer(visual_origin if visual_origin.is_finite() else start, shot.position, shot.caliber.tracer_color)
	if shot.alive:
		_flying.append(shot)


## Drops every projectile still in flight (scene restart).
func clear() -> void:
	_flying.clear()


func flying_count() -> int:
	return _flying.size()


func _physics_process(delta: float) -> void:
	if _flying.is_empty():
		return
	var space := get_world_3d().direct_space_state
	var i := _flying.size() - 1
	while i >= 0:
		var shot := _flying[i]
		var from := shot.position
		shot.velocity += Vector3.DOWN * 9.8 * delta
		BallisticsRaycaster.trace(space, shot, shot.speed * delta)  # Drag is applied along the sweep.
		shot.age += delta
		_show_tracer(from, shot.position, shot.caliber.tracer_color)
		if not shot.alive or shot.speed < MIN_SPEED or shot.age > MAX_FLIGHT_TIME or shot.position.y < -100.0:
			_flying.remove_at(i)
		i -= 1


func _process(delta: float) -> void:
	for i in TRACER_COUNT:
		if _tracer_age[i] < TRACER_LIFE:
			_tracer_age[i] += delta
			if _tracer_age[i] >= TRACER_LIFE:
				_tracers[i].visible = false
			else:
				_tracer_materials[i].albedo_color.a = 0.6 * (1.0 - _tracer_age[i] / TRACER_LIFE)


func _show_tracer(from: Vector3, to: Vector3, color: Color) -> void:
	var span := to - from
	var length := span.length()
	if length < 0.5:
		return
	var index := _tracer_head
	_tracer_head = (_tracer_head + 1) % TRACER_COUNT
	var direction := span / length
	var up := Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT
	var tracer := _tracers[index]
	tracer.global_transform = Transform3D(Basis.looking_at(direction, up).scaled_local(Vector3(1.0, 1.0, length)), from + span * 0.5)
	_tracer_materials[index].albedo_color = Color(color.r, color.g, color.b, 0.6)
	_tracer_age[index] = 0.0
	tracer.visible = true
