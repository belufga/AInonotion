class_name Explosion
extends RefCounted
## Dual-radius explosion model.
##
## 1. Overpressure shockwave: peak pressure from Sadovsky's free-air blast formula, turned into
##    a radial impulse on every body in range and into blast trauma on body parts.
## 2. Shrapnel: high-velocity fragments traced in a spherical pattern with the same penetrating
##    ballistics as bullets, so they lacerate, fracture and perforate organs.
## 3. Epicentre gibbing: humanoids whose torso is inside the lethal radius come apart.

const POSITIVE_PHASE := 0.0015  ## s; duration of the pressure pulse for a small charge.
const IMPULSE_GAIN := 10.0      ## Gameplay exaggeration; real grenades barely move a body.
const MAX_VELOCITY_CHANGE := 22.0
const REAL_FRAGMENTS := 1200.0  ## Fragments a real casing throws; the traced rays stand in for them.
const BODY_AREA := 0.5          ## m^2 a person presents to the blast.
const MAX_AIMED_FRAGMENTS := 16


## Peak incident overpressure in kPa at `distance` metres from `tnt_kg` of TNT (Sadovsky).
static func overpressure(distance: float, tnt_kg: float) -> float:
	var z := maxf(distance, 0.25) / pow(tnt_kg, 1.0 / 3.0)
	return 84.0 / z + 270.0 / (z * z) + 700.0 / (z * z * z)


static func detonate(context: Node3D, origin: Vector3, tnt_kg := 0.23, shrapnel := 96, gib_radius := 1.3, attacker: Node = null) -> void:
	var space := context.get_world_3d().direct_space_state
	var humanoids := _shockwave(space, origin, tnt_kg, gib_radius, attacker)
	_shrapnel(space, origin, shrapnel, attacker, humanoids)
	_effects(context, space, origin, tnt_kg)


## Returns every humanoid the wave reached, for the fragment pass.
static func _shockwave(space: PhysicsDirectSpaceState3D, origin: Vector3, tnt_kg: float, gib_radius: float, attacker: Node) -> Array[Humanoid]:
	var sphere := SphereShape3D.new()
	sphere.radius = 14.0 * pow(tnt_kg, 1.0 / 3.0)  # Under ~4 kPa beyond this.
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, origin)
	query.collision_mask = Layers.PROPS | Layers.BODY | Layers.GIBS | Layers.PROJECTILES
	var seen := {}
	var reached := {}
	var to_gib := {}
	for hit: Dictionary in space.intersect_shape(query, 256):
		var node := hit.collider as Node3D
		if node == null or seen.has(node):
			continue
		seen[node] = true
		var offset := node.global_position - origin
		var distance := offset.length()
		var direction := offset / distance if distance > 0.05 else Vector3.UP
		# Solid cover between the charge and the target takes most of the wave.
		var cover := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, node.global_position, Layers.WORLD))
		var exposed := cover.is_empty()
		var pressure := overpressure(distance, tnt_kg) * (1.0 if exposed else 0.25)
		if pressure < 3.0:
			continue
		var push := (direction + Vector3.UP * 0.25).normalized()
		var hitbox := HitboxComponent.of(node)
		if hitbox != null:
			var humanoid := Layers.entity_root(node) as Humanoid
			if humanoid != null:
				reached[humanoid] = true
				if exposed and distance < gib_radius and hitbox.region == HitboxComponent.Region.TORSO:
					to_gib[humanoid] = true
			hitbox.apply_blast(pressure, push * _impulse(pressure, hitbox.bone.mass), origin, attacker)
			continue
		var body := node as RigidBody3D
		if body != null and not body.freeze:
			body.apply_impulse(push * _impulse(pressure, body.mass), Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.1)
		var health := HealthComponent.of(node)
		if health != null:
			var info := DamageInfo.make(DamageInfo.Type.BLAST, node.global_position, direction, attacker)
			info.overpressure = pressure
			health.apply_damage(info)
	var survivors: Array[Humanoid] = []
	for humanoid: Humanoid in reached:
		if to_gib.has(humanoid):
			humanoid.gore.gib(origin)
		else:
			survivors.append(humanoid)
	return survivors


## Specific impulse times presented area, with area estimated from mass.
static func _impulse(pressure_kpa: float, mass: float) -> float:
	var area := pow(mass / 500.0, 2.0 / 3.0)
	return minf(pressure_kpa * 1000.0 * POSITIVE_PHASE * 0.5 * area * IMPULSE_GAIN, mass * MAX_VELOCITY_CHANGE)


static func _shrapnel(space: PhysicsDirectSpaceState3D, origin: Vector3, count: int, attacker: Node, humanoids: Array[Humanoid]) -> void:
	var golden := PI * (3.0 - sqrt(5.0))
	for i in count:
		# Fibonacci sphere with jitter: even coverage without visible structure.
		var y := 1.0 - 2.0 * (i + 0.5) / count
		var ring := sqrt(1.0 - y * y)
		var angle := golden * i
		_fragment(space, origin, Vector3(cos(angle) * ring, y, sin(angle) * ring)
			+ Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.12, attacker)
	# A real casing throws over a thousand fragments, far more than the rays above. Bodies are
	# therefore importance-sampled: each gets as many aimed fragments as the true fragment
	# density would put on a person at that distance (about 5 at 3 m, 2 at 5 m, 1 in 5 at 15 m).
	for humanoid in humanoids:
		var distance := maxf(humanoid.hips_position().distance_to(origin), 0.5)
		var expected := REAL_FRAGMENTS * BODY_AREA / (4.0 * PI * distance * distance)
		var aimed := mini(int(expected) + int(randf() < fmod(expected, 1.0)), MAX_AIMED_FRAGMENTS)
		for i in aimed:
			var bone := humanoid.rig.bones[humanoid.rig.order.pick_random()]
			var target := bone.global_position + Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.08
			_fragment(space, origin, target - origin, attacker)


static func _fragment(space: PhysicsDirectSpaceState3D, origin: Vector3, direction: Vector3, attacker: Node) -> void:
	var cal := Caliber.fragment_m67()
	var dir := direction.normalized()
	var shot := BallisticShot.create(cal, origin + dir * 0.05, dir, attacker,
		cal.muzzle_velocity * randf_range(0.7, 1.0), DamageInfo.Type.SHRAPNEL)
	BallisticsRaycaster.trace(space, shot, 30.0)


static func _effects(context: Node3D, space: PhysicsDirectSpaceState3D, origin: Vector3, tnt_kg: float) -> void:
	var tree := context.get_tree()
	var size := pow(tnt_kg / 0.23, 1.0 / 3.0)
	Sfx.play(&"explosion", origin, 6.0)
	tree.call_group(&"player", &"on_explosion", origin, size)
	var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * 1.5, Layers.WORLD))
	if not ground.is_empty():
		BloodFX.scorch(ground.position, ground.normal, 1.3 * size)
	BloodFX.debris_particles.emit(origin, Vector3.UP, 4.0, 12.0, 80.0, 1.0, Color(0.25, 0.22, 0.2))

	var root := Node3D.new()
	root.name = "ExplosionFX"
	tree.current_scene.add_child(root)
	root.global_position = origin
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.35)
	light.light_energy = 40.0
	light.omni_range = 18.0 * size
	root.add_child(light)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.62, 0.2, 0.9)
	var fireball := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.5
	ball.height = 1.0
	fireball.mesh = ball
	fireball.material_override = material
	fireball.scale = Vector3.ONE * 0.4
	fireball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fireball)

	var smoke_material := StandardMaterial3D.new()
	smoke_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smoke_material.vertex_color_use_as_albedo = true
	smoke_material.albedo_color = Color(0.16, 0.15, 0.14, 0.55)
	var puff := QuadMesh.new()
	puff.size = Vector2(1.6, 1.6) * size
	puff.material = smoke_material
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 70.0
	process.initial_velocity_min = 1.0
	process.initial_velocity_max = 4.5
	process.gravity = Vector3(0.0, 0.8, 0.0)
	process.damping_min = 1.5
	process.damping_max = 2.5
	process.scale_min = 0.6
	process.scale_max = 1.5
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	fade.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	var smoke := GPUParticles3D.new()
	smoke.one_shot = true
	smoke.explosiveness = 0.9
	smoke.amount = 20
	smoke.lifetime = 2.4
	smoke.process_material = process
	smoke.draw_pass_1 = puff
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(smoke)

	var tween := root.create_tween()
	tween.set_parallel(true)
	tween.tween_property(fireball, "scale", Vector3.ONE * 3.2 * size, 0.18).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.24)
	tween.tween_property(light, "light_energy", 0.0, 0.3)
	tween.chain().tween_interval(2.6)
	tween.chain().tween_callback(root.queue_free)
