class_name PropFactory
extends RefCounted
## Builds world geometry and physics props from primitives. Every body is tagged with its
## ballistic surface (and wall thickness when hollow) so bullets know what they are hitting.

static var _materials: Dictionary = {}


static func static_box(size: Vector3, position: Vector3, surface: StringName, color: Color, yaw := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.set_meta(BallisticMaterial.META_SURFACE, surface)
	_add_box(body, size, surface, color)
	body.position = position
	body.rotation.y = yaw
	return body


static func rigid_box(size: Vector3, mass: float, surface: StringName, color: Color, wall := 0.0) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.mass = mass
	body.collision_layer = Layers.PROPS
	body.collision_mask = Layers.WORLD | Layers.PROPS | Layers.BODY | Layers.PLAYER | Layers.PROJECTILES
	body.set_meta(BallisticMaterial.META_SURFACE, surface)
	if wall > 0.0:
		body.set_meta(BallisticMaterial.META_WALL, wall)
	body.add_to_group(Layers.GROUP_ENTITY)
	_add_box(body, size, surface, color)
	return body


## Hollow wooden crate: 20 mm boards, so rifle rounds go straight through both sides.
static func crate(edge := 0.8) -> RigidBody3D:
	var body := rigid_box(Vector3.ONE * edge, 18.0, &"wood", Color(0.55, 0.38, 0.2), 0.02)
	body.name = "Crate"
	return body


## Solid 6 mm steel plate: stops pistol rounds and buckshot, not 7.62.
static func steel_plate() -> RigidBody3D:
	var body := rigid_box(Vector3(1.2, 1.5, 0.006), 85.0, &"metal", Color(0.42, 0.44, 0.47))
	body.name = "SteelPlate"
	return body


static func concrete_block() -> RigidBody3D:
	var body := rigid_box(Vector3(0.5, 0.5, 1.0), 300.0, &"concrete", Color(0.62, 0.6, 0.57))
	body.name = "ConcreteBlock"
	return body


## A rolling car body on four suspended wheels. Not drivable; it is a heavy prop to push,
## weld, blow up and run over ragdolls with.
static func vehicle() -> VehicleBody3D:
	var car := VehicleBody3D.new()
	car.name = "Vehicle"
	car.mass = 900.0
	car.collision_layer = Layers.PROPS
	car.collision_mask = Layers.WORLD | Layers.PROPS | Layers.BODY | Layers.PLAYER | Layers.PROJECTILES
	car.set_meta(BallisticMaterial.META_SURFACE, &"metal")
	car.set_meta(BallisticMaterial.META_WALL, 0.002)
	car.add_to_group(Layers.GROUP_ENTITY)
	car.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	car.center_of_mass = Vector3(0.0, 0.25, 0.0)
	var paint := Color(0.16, 0.3, 0.5)
	_add_box(car, Vector3(1.8, 0.55, 4.1), &"metal", paint, Vector3(0.0, 0.6, 0.0))
	_add_box(car, Vector3(1.6, 0.5, 2.0), &"metal", paint.darkened(0.25), Vector3(0.0, 1.12, 0.2))
	var tyre := _material(&"rubber", Color(0.07, 0.07, 0.07))
	for x: float in [-0.85, 0.85]:
		for z: float in [-1.35, 1.35]:
			var wheel := VehicleWheel3D.new()
			wheel.position = Vector3(x, 0.55, z)
			wheel.wheel_radius = 0.34
			wheel.wheel_rest_length = 0.18
			wheel.suspension_travel = 0.2
			wheel.suspension_stiffness = 45.0
			wheel.damping_compression = 3.0
			wheel.damping_relaxation = 4.0
			wheel.wheel_friction_slip = 2.5
			wheel.use_as_steering = z < 0.0
			wheel.use_as_traction = z > 0.0
			var rim := CylinderMesh.new()
			rim.top_radius = 0.34
			rim.bottom_radius = 0.34
			rim.height = 0.22
			rim.radial_segments = 16
			var visual := MeshInstance3D.new()
			visual.mesh = rim
			visual.material_override = tyre
			visual.rotation.z = PI / 2.0
			wheel.add_child(visual)
			car.add_child(wheel)
	car.brake = 6.0
	return car


static func _add_box(body: CollisionObject3D, size: Vector3, surface: StringName, color: Color, offset := Vector3.ZERO) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = offset
	body.add_child(collider)
	var mesh := BoxMesh.new()
	mesh.size = size
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = _material(surface, color)
	visual.position = offset
	body.add_child(visual)


static func _material(surface: StringName, color: Color) -> StandardMaterial3D:
	var key := "%s|%s" % [surface, color]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	match surface:
		&"metal":
			material.metallic = 0.75
			material.roughness = 0.4
		&"wood":
			material.roughness = 0.8
		&"rubber":
			material.roughness = 0.9
		_:
			material.roughness = 0.9
	_materials[key] = material
	return material
