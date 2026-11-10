extends Node3D
## Sandbox test range. Builds the environment, a firing range with cover made of each ballistic
## material, a window, a raised platform, some props and a handful of NPCs, then drops the
## player in. Everything is constructed in code so the project carries no binary assets.

const CONCRETE := Color(0.6, 0.59, 0.57)

var entities: Node3D
var player: Player


func _ready() -> void:
	_build_environment()
	_build_level()
	entities = Node3D.new()
	entities.name = "Entities"
	entities.add_to_group(Layers.GROUP_ENTITY_CONTAINER)
	add_child(entities)
	_populate()
	player = Player.new()
	player.name = "Player"
	player.position = Vector3(0.0, 0.05, 9.0)
	add_child(player)


func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.3, 0.45, 0.7)
	sky_material.sky_horizon_color = Color(0.7, 0.76, 0.82)
	sky_material.ground_horizon_color = Color(0.6, 0.62, 0.64)
	sky_material.ground_bottom_color = Color(0.25, 0.25, 0.26)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.9
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 0.5
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)

	# Lets GPU blood and debris particles die on the floor and on props instead of falling through.
	var heightfield := GPUParticlesCollisionHeightField3D.new()
	heightfield.size = Vector3(80.0, 16.0, 80.0)
	heightfield.position = Vector3(0.0, 7.0, -6.0)
	heightfield.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_1024
	heightfield.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_ALWAYS
	add_child(heightfield)


func _build_level() -> void:
	var floor_body := PropFactory.static_box(Vector3(160.0, 1.0, 160.0), Vector3(0.0, -0.5, 0.0), &"concrete", CONCRETE)
	floor_body.name = "Floor"
	(floor_body.get_child(1) as MeshInstance3D).material_override = _tile_material()
	add_child(floor_body)

	# Backstop and side walls of the range.
	add_child(PropFactory.static_box(Vector3(30.0, 4.0, 0.5), Vector3(0.0, 2.0, -24.0), &"concrete", CONCRETE.darkened(0.1)))
	add_child(PropFactory.static_box(Vector3(0.5, 4.0, 20.0), Vector3(-15.0, 2.0, -14.0), &"concrete", CONCRETE.darkened(0.1)))
	add_child(PropFactory.static_box(Vector3(0.5, 4.0, 20.0), Vector3(15.0, 2.0, -14.0), &"concrete", CONCRETE.darkened(0.1)))

	# One piece of cover per material: 7.62 defeats the wood and the steel, 9 mm neither.
	add_child(PropFactory.static_box(Vector3(3.0, 2.2, 0.1), Vector3(-7.0, 1.1, -7.0), &"wood", Color(0.5, 0.34, 0.18)))
	add_child(PropFactory.static_box(Vector3(2.6, 2.2, 0.006), Vector3(7.0, 1.1, -7.0), &"metal", Color(0.4, 0.42, 0.45)))
	add_child(PropFactory.static_box(Vector3(3.5, 1.15, 0.4), Vector3(0.0, 0.575, -3.0), &"concrete", CONCRETE.lightened(0.08)))

	# Window in a concrete frame.
	var frame_color := CONCRETE.darkened(0.2)
	add_child(PropFactory.static_box(Vector3(0.3, 2.6, 0.3), Vector3(-11.95, 1.3, -1.0), &"concrete", frame_color))
	add_child(PropFactory.static_box(Vector3(0.3, 2.6, 0.3), Vector3(-10.05, 1.3, -1.0), &"concrete", frame_color))
	add_child(PropFactory.static_box(Vector3(2.2, 0.8, 0.3), Vector3(-11.0, 0.4, -1.0), &"concrete", frame_color))
	add_child(PropFactory.static_box(Vector3(2.2, 0.4, 0.3), Vector3(-11.0, 2.4, -1.0), &"concrete", frame_color))

	# Raised platform with a ramp.
	add_child(PropFactory.static_box(Vector3(7.0, 1.2, 7.0), Vector3(10.5, 0.6, -19.0), &"concrete", CONCRETE.darkened(0.05)))
	var ramp := PropFactory.static_box(Vector3(3.0, 0.3, 6.4), Vector3(10.5, 0.52, -12.6), &"concrete", CONCRETE.darkened(0.05))
	ramp.rotation.x = deg_to_rad(11.0)
	add_child(ramp)


func _populate() -> void:
	var facing_player := 0.0
	for spot: Vector3 in [Vector3(-3.5, 0, -10), Vector3(-1.2, 0, -11.5), Vector3(1.4, 0, -10.5), Vector3(3.8, 0, -12)]:
		SpawnCatalog.spawn(&"civilian", spot, facing_player + randf_range(-0.6, 0.6), entities)
	SpawnCatalog.spawn(&"soldier", Vector3(-6.0, 0, -14.0), facing_player, entities)
	SpawnCatalog.spawn(&"soldier", Vector3(6.0, 0, -15.0), facing_player, entities)
	SpawnCatalog.spawn(&"civilian", Vector3(-7.0, 0, -8.6), facing_player, entities)   # Behind the wooden wall.
	SpawnCatalog.spawn(&"civilian", Vector3(7.0, 0, -8.6), facing_player, entities)    # Behind the steel plate.
	SpawnCatalog.spawn(&"civilian", Vector3(10.5, 1.2, -19.0), facing_player, entities)

	for spot: Vector3 in [Vector3(9.5, 0, -8.0), Vector3(10.4, 0, -8.5), Vector3(9.9, 0, -9.3)]:
		SpawnCatalog.spawn(&"barrel", spot, 0.0, entities)
	for spot: Vector3 in [Vector3(-3.0, 0, 3.0), Vector3(-3.9, 0, 3.2), Vector3(-3.4, 0.82, 3.1), Vector3(4.0, 0, 2.0)]:
		SpawnCatalog.spawn(&"crate", spot, randf() * 0.4, entities)
	SpawnCatalog.spawn(&"steel_plate", Vector3(3.0, 0, -6.0), 0.3, entities)
	SpawnCatalog.spawn(&"vehicle", Vector3(-11.0, 0, 6.0), PI / 2.0, entities)
	SpawnCatalog.spawn(&"ak47", Vector3(4.0, 0.85, 2.0), 0.8, entities)

	var glass := BreakableGlass.create()
	glass.position = Vector3(-11.0, 1.5, -1.0)
	entities.add_child(glass)


## Two-metre concrete slabs with dark joints, so distance and blood both read against the floor.
func _tile_material() -> StandardMaterial3D:
	var image := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var edge := x < 1 or y < 1
			var grain := 0.54 + 0.05 * sin(x * 1.7 + y * 0.6) * sin(y * 1.3)
			image.set_pixel(x, y, Color(0.3, 0.3, 0.3) if edge else Color(grain, grain, grain * 0.98))
	image.generate_mipmaps()
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3(0.5, 0.5, 0.5)
	material.roughness = 0.92
	return material
