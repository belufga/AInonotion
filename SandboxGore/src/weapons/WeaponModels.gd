class_name WeaponModels
extends RefCounted
## Procedural weapon meshes built from primitives, used for first-person viewmodels, world
## pickups and NPC-held weapons alike. Model space: barrel along -Z, +Y up, grip near the origin.
## Animated parts are named child nodes ("Slide", "Pump", "Bolt"); "Muzzle" marks the barrel tip.

const VIEWMODEL_FOV := 55.0
const META_VIEWMODEL := &"viewmodel"

static var _materials: Dictionary = {}


## Viewmodel materials render with their own field of view and a compressed depth range, so the
## weapon keeps its shape at any camera FOV and does not poke through nearby walls.
static func material(color: Color, metallic: float, roughness: float, viewmodel: bool, emission := Color.BLACK) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%s|%s" % [color, metallic, roughness, viewmodel, emission]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if emission != Color.BLACK:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = 2.5
	if viewmodel:
		m.use_fov_override = true
		m.fov_override = VIEWMODEL_FOV
		m.use_z_clip_scale = true
		m.z_clip_scale = 0.35
	_materials[key] = m
	return m


static func build(id: StringName, viewmodel := false) -> Node3D:
	match id:
		&"pistol":
			return pistol(viewmodel)
		&"shotgun":
			return shotgun(viewmodel)
		&"grenade":
			return grenade(viewmodel)
		&"toolgun":
			return toolgun(viewmodel)
	return ak47(viewmodel)


static func ak47(viewmodel := false) -> Node3D:
	var root := _root("AK47", viewmodel)
	var steel := material(Color(0.13, 0.13, 0.14), 0.8, 0.45, viewmodel)
	var wood := material(Color(0.42, 0.22, 0.1), 0.0, 0.6, viewmodel)
	_box(root, Vector3(0.045, 0.06, 0.26), Vector3(0, 0, -0.05), steel)
	_cylinder(root, 0.009, 0.34, Vector3(0, 0.012, -0.35), steel)
	_cylinder(root, 0.008, 0.2, Vector3(0, 0.036, -0.27), steel)
	_box(root, Vector3(0.042, 0.05, 0.2), Vector3(0, 0.008, -0.27), wood)
	_box(root, Vector3(0.035, 0.07, 0.24), Vector3(0, -0.018, 0.2), wood, Vector3(7, 0, 0))
	_box(root, Vector3(0.03, 0.09, 0.04), Vector3(0, -0.07, 0.05), wood, Vector3(-15, 0, 0))
	_box(root, Vector3(0.028, 0.17, 0.06), Vector3(0, -0.105, -0.075), steel, Vector3(18, 0, 0), "Magazine")
	_box(root, Vector3(0.006, 0.04, 0.012), Vector3(0, 0.05, -0.48), steel)
	_box(root, Vector3(0.022, 0.016, 0.02), Vector3(0, 0.042, -0.1), steel)
	_box(root, Vector3(0.03, 0.012, 0.03), Vector3(0.03, 0.016, -0.03), steel, Vector3.ZERO, "Bolt")
	_muzzle(root, Vector3(0, 0.012, -0.52))
	return root


static func pistol(viewmodel := false) -> Node3D:
	var root := _root("Pistol", viewmodel)
	var polymer := material(Color(0.09, 0.09, 0.1), 0.1, 0.7, viewmodel)
	var steel := material(Color(0.2, 0.2, 0.22), 0.85, 0.35, viewmodel)
	_box(root, Vector3(0.028, 0.03, 0.15), Vector3(0, 0, -0.06), polymer)
	_box(root, Vector3(0.028, 0.1, 0.045), Vector3(0, -0.06, 0.0), polymer, Vector3(-12, 0, 0))
	var slide := _box(root, Vector3(0.03, 0.03, 0.18), Vector3(0, 0.03, -0.065), steel, Vector3.ZERO, "Slide")
	_box(slide, Vector3(0.004, 0.008, 0.006), Vector3(0, 0.019, -0.08), steel)
	_box(slide, Vector3(0.014, 0.008, 0.008), Vector3(0, 0.019, 0.08), steel)
	_muzzle(root, Vector3(0, 0.03, -0.16))
	return root


static func shotgun(viewmodel := false) -> Node3D:
	var root := _root("Shotgun", viewmodel)
	var steel := material(Color(0.11, 0.11, 0.12), 0.8, 0.4, viewmodel)
	var wood := material(Color(0.33, 0.17, 0.08), 0.0, 0.55, viewmodel)
	_box(root, Vector3(0.045, 0.06, 0.22), Vector3(0, 0, -0.02), steel)
	_cylinder(root, 0.011, 0.5, Vector3(0, 0.015, -0.38), steel)
	_cylinder(root, 0.011, 0.4, Vector3(0, -0.012, -0.33), steel)
	_box(root, Vector3(0.04, 0.04, 0.14), Vector3(0, -0.012, -0.3), wood, Vector3.ZERO, "Pump")
	_box(root, Vector3(0.035, 0.08, 0.3), Vector3(0, -0.022, 0.24), wood, Vector3(6, 0, 0))
	_box(root, Vector3(0.006, 0.008, 0.006), Vector3(0, 0.03, -0.62), steel)
	_muzzle(root, Vector3(0, 0.015, -0.64))
	return root


static func grenade(viewmodel := false) -> Node3D:
	var root := _root("Grenade", viewmodel)
	var olive := material(Color(0.22, 0.27, 0.13), 0.3, 0.6, viewmodel)
	var steel := material(Color(0.5, 0.5, 0.48), 0.9, 0.35, viewmodel)
	var body := SphereMesh.new()
	body.radius = 0.032
	body.height = 0.072
	body.radial_segments = 14
	body.rings = 7
	_part(root, body, olive, Vector3.ZERO)
	var fuze := CylinderMesh.new()
	fuze.top_radius = 0.011
	fuze.bottom_radius = 0.013
	fuze.height = 0.03
	fuze.radial_segments = 10
	_part(root, fuze, steel, Vector3(0, 0.045, 0))
	_box(root, Vector3(0.012, 0.075, 0.004), Vector3(0, 0.012, -0.034), steel, Vector3(-8, 0, 0), "Spoon")
	_box(root, Vector3(0.022, 0.022, 0.003), Vector3(0.022, 0.05, 0), steel, Vector3.ZERO, "Pin")
	return root


static func toolgun(viewmodel := false) -> Node3D:
	var root := _root("Toolgun", viewmodel)
	var shell := material(Color(0.75, 0.76, 0.78), 0.6, 0.3, viewmodel)
	var dark := material(Color(0.1, 0.1, 0.12), 0.2, 0.6, viewmodel)
	var glow := material(Color(0.1, 0.5, 0.9), 0.0, 0.3, viewmodel, Color(0.2, 0.7, 1.0))
	_box(root, Vector3(0.05, 0.07, 0.2), Vector3(0, 0, -0.04), shell)
	_box(root, Vector3(0.032, 0.1, 0.045), Vector3(0, -0.07, 0.03), dark, Vector3(-14, 0, 0))
	_cylinder(root, 0.02, 0.14, Vector3(0, 0.005, -0.2), dark)
	_cylinder(root, 0.024, 0.02, Vector3(0, 0.005, -0.27), glow, "Emitter")
	_box(root, Vector3(0.04, 0.012, 0.06), Vector3(0, 0.041, -0.02), glow, Vector3(-20, 0, 0), "Screen")
	_muzzle(root, Vector3(0, 0.005, -0.29))
	return root


## Approximate bounding box of a weapon model, for pickup collision shapes.
static func bounds(id: StringName) -> Vector3:
	match id:
		&"pistol":
			return Vector3(0.04, 0.14, 0.2)
		&"shotgun":
			return Vector3(0.05, 0.12, 0.95)
		&"grenade":
			return Vector3(0.07, 0.09, 0.07)
	return Vector3(0.05, 0.2, 0.85)


static func _root(p_name: String, viewmodel: bool) -> Node3D:
	var root := Node3D.new()
	root.name = p_name
	root.set_meta(META_VIEWMODEL, viewmodel)
	return root


static func _part(parent: Node3D, mesh: Mesh, mat: Material, position: Vector3, rotation_degrees := Vector3.ZERO, node_name := "") -> MeshInstance3D:
	var owner_root := parent
	while not owner_root.has_meta(META_VIEWMODEL):
		owner_root = owner_root.get_parent()
	var viewmodel: bool = owner_root.get_meta(META_VIEWMODEL)
	var instance := MeshInstance3D.new()
	if node_name != "":
		instance.name = node_name
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = position
	instance.rotation_degrees = rotation_degrees
	instance.layers = Layers.VIS_VIEWMODEL if viewmodel else Layers.VIS_WORLD
	if viewmodel:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


static func _box(parent: Node3D, size: Vector3, position: Vector3, mat: Material, rotation_degrees := Vector3.ZERO, node_name := "") -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _part(parent, mesh, mat, position, rotation_degrees, node_name)


## Cylinder lying along the barrel axis.
static func _cylinder(parent: Node3D, radius: float, length: float, position: Vector3, mat: Material, node_name := "") -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 12
	mesh.rings = 1
	return _part(parent, mesh, mat, position, Vector3(90, 0, 0), node_name)


static func _muzzle(root: Node3D, position: Vector3) -> void:
	var marker := Marker3D.new()
	marker.name = "Muzzle"
	marker.position = position
	root.add_child(marker)
