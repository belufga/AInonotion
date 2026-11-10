extends Node3D
## Headless integration tests for the simulation systems.
## Run: godot --headless --fixed-fps 60 --path . res://tests/TestRunner.tscn [-- name_filter]

const AWAKE := VitalsComponent.Consciousness.AWAKE
const DEAD := VitalsComponent.Consciousness.DEAD

var _failures := 0
var _checks := 0
var _entities: Node3D


func _ready() -> void:
	seed(20261110)
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		filter = args[0]
	_build_arena()
	await _frames(3)
	for method in get_method_list():
		var test: String = method.name
		if not test.begins_with("test_") or (filter != "" and not test.contains(filter)):
			continue
		_reset()
		await _frames(2)
		print("--- ", test)
		await call(test)
	print("RESULT: %s (%d checks, %d failed)" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


# --- helpers -------------------------------------------------------------------------------

func _build_arena() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = Layers.WORLD
	ground.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(400.0, 1.0, 400.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	ground.add_child(collider)
	ground.position = Vector3(0.0, -0.5, 0.0)
	add_child(ground)
	_entities = Node3D.new()
	_entities.name = "Entities"
	_entities.add_to_group(Layers.GROUP_ENTITY_CONTAINER)
	add_child(_entities)


func _reset() -> void:
	for child in _entities.get_children():
		child.queue_free()
	BloodFX.clear()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _seconds(seconds: float) -> void:
	await _frames(int(seconds * Engine.physics_ticks_per_second))


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _spawn_npc(at: Vector3, armed := false, yaw := 0.0) -> Humanoid:
	var npc := Humanoid.new()
	npc.armed = armed
	npc.wanders = false
	npc.position = at
	npc.rotation.y = yaw
	_entities.add_child(npc)
	return npc


func _shoot(caliber: Caliber, from: Vector3, to: Vector3) -> BallisticShot:
	var shot := BallisticShot.create(caliber, from, to - from)
	shot.record = true
	BallisticsRaycaster.trace(get_world_3d().direct_space_state, shot, from.distance_to(to) + 60.0)
	return shot


func _bone(npc: Humanoid, part: StringName) -> PhysicalBone3D:
	return npc.rig.bones[part]


func _organ(npc: Humanoid, organ_name: StringName) -> OrganVolume3D:
	for organ in npc.rig.organs:
		if organ.organ_name == organ_name:
			return organ
	return null


func _status(npc: Humanoid) -> String:
	return "hips=%.2f tilt=%.0f state=%s %s" % [npc.ragdoll.hips_height(), rad_to_deg(npc.ragdoll.tilt()),
		NPCBrain.State.keys()[npc.brain.state], VitalsComponent.Consciousness.keys()[npc.vitals.consciousness]]


# --- tests ---------------------------------------------------------------------------------

func test_a_scripts_compile() -> void:
	var failed: PackedStringArray = []
	var pending: Array[String] = ["res://src"]
	var count := 0
	while not pending.is_empty():
		var dir_path: String = pending.pop_back()
		for sub in DirAccess.get_directories_at(dir_path):
			pending.append(dir_path + "/" + sub)
		for file in DirAccess.get_files_at(dir_path):
			if file.ends_with(".gd"):
				count += 1
				var script := load(dir_path + "/" + file) as GDScript
				if script == null or not script.can_instantiate():
					failed.append(file)
	_check(failed.is_empty(), "%d scripts compile %s" % [count, failed])


func test_a_jolt_is_the_active_physics_engine() -> void:
	# An unknown engine name falls back to Godot Physics without a warning, so the project
	# setting alone proves nothing. Jolt reports face_index -1 for a ray hit on a trimesh;
	# Godot Physics reports the triangle.
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(PackedVector3Array([Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(0, 0, 1)]))
	var collider := CollisionShape3D.new()
	collider.shape = shape
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.add_child(collider)
	body.position = Vector3(60, 5, 60)
	_entities.add_child(body)
	await _frames(2)
	var query := PhysicsRayQueryParameters3D.create(body.position + Vector3.UP, body.position + Vector3.DOWN, Layers.WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	_check(not hit.is_empty() and hit.face_index == -1, "Jolt is the active 3D physics engine (setting \"%s\", trimesh ray face_index %s)"
		% [ProjectSettings.get_setting("physics/3d/physics_engine"), hit.get("face_index")])


func test_b_npc_stands() -> void:
	var npc := _spawn_npc(Vector3.ZERO)
	for i in 8:
		await _seconds(0.5)
		print("    t=%.1f %s" % [(i + 1) * 0.5, _status(npc)])
	_check(absf(npc.ragdoll.hips_height() - Anatomy.STAND_HEIGHT) < 0.12, "hips stay at standing height")
	_check(rad_to_deg(npc.ragdoll.tilt()) < 12.0, "pelvis stays upright")
	_check(npc.brain.state == NPCBrain.State.IDLE, "still idle, not fallen")
	_check(_bone(npc, Anatomy.HEAD).global_position.y > 1.5, "head is up")


func test_c_npc_walks() -> void:
	var npc := _spawn_npc(Vector3.ZERO)
	await _seconds(1.0)
	npc.brain._destination = Vector3(0.0, 0.0, -6.0)
	npc.brain._enter(NPCBrain.State.WANDER)
	for i in 8:
		await _seconds(0.5)
		print("    t=%.1f z=%.2f %s" % [(i + 1) * 0.5, npc.hips_position().z, _status(npc)])
	_check(npc.hips_position().z < -2.5, "walked toward its destination")
	_check(rad_to_deg(npc.ragdoll.tilt()) < 20.0, "stayed upright while walking")


func test_d_headshot_is_instant_death() -> void:
	var npc := _spawn_npc(Vector3.ZERO)
	await _seconds(0.5)
	var brain := _organ(npc, &"Brain").global_position
	var shot := _shoot(Caliber.parabellum_9mm(), brain + Vector3(0, 0, -5), brain + Vector3(0, 0, 5))
	_check(not shot.hits.is_empty() and shot.hits[0].part == Anatomy.HEAD, "bullet entered the head")
	_check(npc.vitals.consciousness == DEAD, "brain hit kills on the same frame (%s)" % npc.vitals.cause_of_death)
	await _frames(2)
	_check(npc.brain.state == NPCBrain.State.DEAD and npc.ragdoll.motor_strength == 0.0, "motor shutdown, permanent ragdoll")
	await _seconds(2.0)
	_check(npc.ragdoll.hips_height() < 0.5, "body collapsed (%s)" % _status(npc))


func test_e_heart_shot_collapses_circulation() -> void:
	var npc := _spawn_npc(Vector3.ZERO)
	await _seconds(0.5)
	var heart := _organ(npc, &"Heart").global_position
	_shoot(Caliber.parabellum_9mm(), heart + Vector3(0, 0, -5), heart + Vector3(0, 0, 5))
	_check(npc.vitals.heart_function < 0.2, "heart perforated (function %.2f)" % npc.vitals.heart_function)
	await _seconds(4.0)
	print("    4 s: ", npc.vitals.summary().replace("\n", " | "))
	_check(npc.vitals.systolic < 30.0, "blood pressure collapses within seconds (%.0f mmHg)" % npc.vitals.systolic)
	_check(not npc.vitals.is_conscious(), "unconscious")
	await _seconds(26.0)
	print("    30 s: ", npc.vitals.summary().replace("\n", " | "))
	_check(npc.vitals.consciousness == DEAD, "dead within 30 s")
	_check(npc.vitals.heart_rate < 5.0, "pulse terminated (%.0f bpm)" % npc.vitals.heart_rate)


func test_f_lung_shot_pneumothorax() -> void:
	var npc := _spawn_npc(Vector3.ZERO)
	var coughs := [0]
	npc.vitals.coughed_blood.connect(func() -> void: coughs[0] += 1)
	await _seconds(0.5)
	var lung := _organ(npc, &"LungR").global_position
	_shoot(Caliber.parabellum_9mm(), lung + Vector3(0, 0, -5), lung + Vector3(0, 0, 5))
	_check(npc.vitals.lung_integrity[1] < 1.0, "right lung punctured (integrity %.2f)" % npc.vitals.lung_integrity[1])
	await _seconds(20.0)
	print("    20 s: ", npc.vitals.summary().replace("\n", " | "))
	_check(npc.vitals.lung_tension[1] > 0.5, "tension pneumothorax builds (%.2f)" % npc.vitals.lung_tension[1])
	_check(npc.vitals.oxygen_saturation < 97.0, "oxygen saturation falling (%.1f%%)" % npc.vitals.oxygen_saturation)
	_check(coughs[0] >= 1, "coughed blood %d times" % coughs[0])
	_check(npc.vitals.stamina < 0.9, "stamina depleted (%.2f)" % npc.vitals.stamina)
	_check(npc.vitals.is_alive(), "still alive after 20 s")


func test_g_femoral_artery_bleeds_out() -> void:
	var npc := _spawn_npc(Vector3.ZERO)
	var beats := [0]
	npc.vitals.heartbeat.connect(func(_pressure: float) -> void: beats[0] += 1)
	await _seconds(0.5)
	var artery := _organ(npc, &"FemoralR").global_position
	_shoot(Caliber.parabellum_9mm(), artery + Vector3(0, 0, -5), artery + Vector3(0, 0, 5))
	var arterial := npc.vitals.wounds.filter(func(w: Wound) -> bool: return w.arterial)
	_check(arterial.size() == 1 and arterial[0].label == &"FemoralR", "femoral artery ruptured")
	var decals: int = BloodFX.stats().decals
	await _seconds(8.0)
	print("    8 s: ", npc.vitals.summary().replace("\n", " | "))
	_check(npc.vitals.blood_volume < 4700.0, "blood volume dropping (%d ml)" % npc.vitals.blood_volume)
	_check(beats[0] >= 8, "pulse drives the arterial spurts (%d beats)" % beats[0])
	_check(BloodFX.stats().decals > decals, "spurts and pooling left decals (%d new)" % (BloodFX.stats().decals - decals))
	_check(npc.vitals.heart_rate > 90.0, "compensatory tachycardia (%d bpm)" % npc.vitals.heart_rate)
	var elapsed := 8.0
	while npc.vitals.is_alive() and elapsed < 150.0:
		await _seconds(2.0)
		elapsed += 2.0
	_check(not npc.vitals.is_alive() and npc.vitals.cause_of_death.contains("hemorrhagic"),
		"died of %s after %.0f s with %d ml left" % [npc.vitals.cause_of_death, elapsed, npc.vitals.blood_volume])


func test_h_knee_shot_fall_and_crawl() -> void:
	var npc := _spawn_npc(Vector3.ZERO)
	await _seconds(0.5)
	var knee := _bone(npc, &"LowerLegR").global_transform * Vector3(0, 0.15, 0)
	_shoot(Caliber.soviet_762x39(), knee + Vector3(0, 0, -5), knee + Vector3(0, 0, 5))
	_check(not npc.leg_functional(Anatomy.RIGHT), "right leg disabled")
	for i in 4:
		await _seconds(1.0)
		print("    t=%d %s" % [i + 1, _status(npc)])
	_check(npc.brain.state == NPCBrain.State.CRAWL, "fell into the crawl state")
	_check(npc.ragdoll.hips_height() < 0.6, "collapsed to the ground")
	_check(npc.vitals.is_conscious(), "still conscious")


func test_i_arm_trauma_drops_weapon() -> void:
	var npc := _spawn_npc(Vector3.ZERO, true)
	await _seconds(0.5)
	_check(npc.is_armed(), "starts armed")
	var arm := _bone(npc, &"LowerArmR").global_position
	_shoot(Caliber.parabellum_9mm(), arm + Vector3(0, 0, -5), arm + Vector3(0, 0, 5))
	await _frames(3)
	_check(not npc.is_armed(), "weapon dropped")
	var pickups := _entities.get_children().filter(func(n: Node) -> bool: return n is WeaponPickup)
	_check(pickups.size() == 1, "dropped rifle became a physics prop")


func test_j_point_blank_buckshot_severs_limb() -> void:
	var npc := _spawn_npc(Vector3.ZERO)
	var severed: Array[StringName] = []
	npc.gore.part_severed.connect(func(part: StringName) -> void: severed.append(part))
	await _seconds(0.5)
	var arm := _bone(npc, &"LowerArmL")
	var target := arm.global_position
	for i in 9:
		var spread := Vector3(randf() - 0.5, randf() - 0.5, 0.0) * 0.03
		_shoot(Caliber.buckshot_00(), target + Vector3(0, 0, -1.0), target + spread)
	_check(severed.has(&"LowerArmL") and npc.rig.hitboxes[&"LowerArmL"].is_severed, "forearm severed %s" % [severed])
	var caps := 0
	for bone: PhysicalBone3D in [arm, _bone(npc, &"UpperArmL")]:
		for child in bone.get_children():
			if child is StumpCap:
				caps += 1
	_check(caps == 2, "stump caps on both sides of the cut")
	var stumps := npc.vitals.wounds.filter(func(w: Wound) -> bool: return w.label == &"stump" and w.arterial)
	_check(stumps.size() == 1, "stump bleeds arterially")
	await _seconds(1.0)
	var gap := arm.global_position.distance_to(_bone(npc, &"UpperArmL").global_position)
	_check(gap > 0.45 and gap < 8.0, "forearm separated from the body without being launched (%.2f m)" % gap)
	_check(npc.vitals.is_alive(), "survives the amputation for now")


func test_k_penetration_by_material() -> void:
	var ak := Caliber.soviet_762x39()
	var nine := Caliber.parabellum_9mm()
	_entities.add_child(PropFactory.static_box(Vector3(2, 2, 0.1), Vector3(0, 1, -3), &"wood", Color.BROWN))
	_entities.add_child(PropFactory.static_box(Vector3(2, 2, 0.006), Vector3(5, 1, -3), &"metal", Color.GRAY))
	_entities.add_child(PropFactory.static_box(Vector3(2, 2, 0.3), Vector3(10, 1, -3), &"concrete", Color.GRAY))
	await _frames(3)
	var shot := _shoot(ak, Vector3(0, 1, -8), Vector3(0, 1, 2))
	_check(shot.hits.size() == 1 and shot.hits[0].energy_out > 800.0, "7.62 passes 10 cm of wood (%.0f J left)" % shot.hits[0].energy_out)
	shot = _shoot(nine, Vector3(0, 1, -8), Vector3(0, 1, 2))
	_check(shot.hits[0].energy_out == 0.0 and not shot.alive, "9 mm stops in 10 cm of wood")
	shot = _shoot(ak, Vector3(5, 1, -8), Vector3(5, 1, 2))
	_check(shot.hits[0].energy_out > 300.0, "7.62 passes 6 mm of steel (%.0f J left)" % shot.hits[0].energy_out)
	shot = _shoot(nine, Vector3(5, 1, -8), Vector3(5, 1, 2))
	_check(not shot.alive, "9 mm stops on 6 mm of steel")
	shot = _shoot(Caliber.buckshot_00(), Vector3(5, 1, -8), Vector3(5, 1, 2))
	_check(not shot.alive, "buckshot stops on 6 mm of steel")
	shot = _shoot(ak, Vector3(10, 1, -8), Vector3(10, 1, 2))
	_check(not shot.alive, "7.62 stops in 30 cm of concrete")


func test_l_rifle_round_exits_the_body() -> void:
	var npc := _spawn_npc(Vector3.ZERO)
	_entities.add_child(PropFactory.static_box(Vector3(4, 3, 0.3), Vector3(0, 1.5, 2.0), &"concrete", Color.GRAY))
	await _seconds(0.5)
	var decals: int = BloodFX.stats().decals
	var abdomen := _bone(npc, Anatomy.SPINE).global_position + Vector3(-0.08, 0, 0)
	var shot := _shoot(Caliber.soviet_762x39(), abdomen + Vector3(0, 0, -5), abdomen + Vector3(0, 0, 5))
	_check(shot.hits.size() >= 2 and shot.hits[0].part == Anatomy.SPINE and shot.hits[0].energy_out > 100.0,
		"7.62 goes through the torso (%.0f J in, %.0f J out)" % [shot.hits[0].energy_in, shot.hits[0].energy_out])
	_check(shot.hits[-1].surface == &"concrete", "and carries on into the wall behind")
	_check(shot.tumbling, "bullet yawed inside the tissue")
	var entry := npc.vitals.wounds.filter(func(w: Wound) -> bool: return w.label == &"wound")
	var exits := npc.vitals.wounds.filter(func(w: Wound) -> bool: return w.label == &"exit wound")
	_check(exits.size() == 1 and entry.size() == 1 and exits[0].rate > entry[0].rate * 2.0,
		"exit wound bleeds %.1f ml/s against %.1f ml/s at the entry" % [exits[0].rate, entry[0].rate])
	_check(BloodFX.stats().decals >= decals + 3, "wound marks and wall splatter placed (%d decals)" % (BloodFX.stats().decals - decals))


func test_m_hybrid_ballistics_bullet_drop() -> void:
	_entities.add_child(PropFactory.static_box(Vector3(30, 30, 1), Vector3(0, 15, -300.5), &"concrete", Color.GRAY))
	await _frames(3)
	var cal := Caliber.soviet_762x39()
	var shot := BallisticShot.create(cal, Vector3(0, 10, 0), Vector3.FORWARD)
	shot.record = true
	Ballistics.fire(shot, 60.0)
	_check(shot.alive and Ballistics.flying_count() == 1, "past hitscan range the shot becomes a simulated projectile")
	_check(absf(shot.position.y - 10.0) < 0.001 and absf(shot.position.z + 60.0) < 0.01, "hitscan segment is straight and instant")
	var frames := 0
	while shot.alive and frames < 240:
		await get_tree().physics_frame
		frames += 1
	_check(shot.hits.size() == 1, "projectile reached the wall at 300 m after %.2f s" % (frames / 60.0))
	if shot.hits.size() == 1:
		var drop: float = 10.0 - shot.hits[0].position.y
		_check(drop > 0.4 and drop < 1.4, "gravity drop over the projectile phase: %.2f m" % drop)
		_check(shot.hits[0].energy_in < 0.8 * cal.muzzle_energy(), "air drag bled energy: %.0f J of %.0f J" % [shot.hits[0].energy_in, cal.muzzle_energy()])


func test_n_frag_grenade() -> void:
	var near := _spawn_npc(Vector3(0.7, 0, 0))
	var far := _spawn_npc(Vector3(0, 0, -4.5))
	var glass := BreakableGlass.create()
	glass.position = Vector3(-5, 1.0, 0)
	glass.rotation.y = PI / 2.0
	_entities.add_child(glass)
	var crate := PropFactory.crate()
	crate.position = Vector3(0, 0.41, 2.2)
	_entities.add_child(crate)
	await _seconds(0.5)
	var grenade := GrenadeProjectile.create()
	_entities.add_child(grenade)
	grenade.global_position = Vector3(0, 0.1, 0)
	grenade.release_spoon()
	var fuse := grenade.fuse_left
	_check(fuse >= 3.5 and fuse <= 4.0, "fuse length %.2f s" % fuse)
	var crate_start := crate.global_position
	var frames := 0
	while is_instance_valid(grenade) and not grenade.exploded and frames < 300:
		await get_tree().physics_frame
		frames += 1
	_check(absf(frames / 60.0 - fuse) < 0.1, "detonated when the fuse ran out (%.2f s)" % (frames / 60.0))
	await _frames(3)
	_check(near.gore.is_gibbed and not near.vitals.is_alive(), "body at the epicentre is gibbed")
	var severed := 0
	for hitbox: HitboxComponent in near.rig.hitboxes.values():
		if hitbox.is_severed:
			severed += 1
	_check(severed >= 5, "multi-joint dismemberment (%d joints)" % severed)
	_check(BloodFX.stats().gibs >= 10, "giblets spawned (%d)" % BloodFX.stats().gibs)
	_check(not is_instance_valid(glass) or glass.is_queued_for_deletion(), "window shattered")
	await _seconds(1.0)
	var moved := crate.global_position.distance_to(crate_start)
	_check(moved > 0.3, "crate thrown by the shockwave (%.2f m)" % moved)
	print("    far NPC: %s hp=%.0f wounds=%d" % [_status(far), far.health.health, far.vitals.wounds.size()])
	_check(far.brain.state != NPCBrain.State.IDLE, "NPC at 4.5 m knocked off its feet")
	_check(far.vitals.wounds.size() >= 1, "shrapnel wounded the NPC at 4.5 m (%d wounds)" % far.vitals.wounds.size())


func test_o_barrel_chain_reaction() -> void:
	var first := ExplosiveBarrel.create()
	first.position = Vector3(0, 0.45, 0)
	_entities.add_child(first)
	var second := ExplosiveBarrel.create()
	second.position = Vector3(1.5, 0.45, 0)
	_entities.add_child(second)
	await _seconds(0.5)
	for i in 3:
		_shoot(Caliber.soviet_762x39(), Vector3(0, 0.5, -6), Vector3(0, 0.5, 2))
	_check(first.health.dead, "barrel destroyed by rifle fire")
	await _seconds(1.0)
	_check(not is_instance_valid(first) and not is_instance_valid(second), "second barrel set off by the first")


func test_p_decal_ring_buffer_is_bounded() -> void:
	var pool: DecalRingPool = BloodFX.decals
	for i in 1000:
		BloodFX.blood_splat(Vector3(randf() * 20.0, 0, randf() * 20.0), Vector3.UP, 0.4)
	_check(pool.get_child_count() == pool.capacity, "1000 splats live in %d pooled decal nodes" % pool.get_child_count())
	_check(pool.used_count() == pool.capacity, "ring is full and recycling")


func test_q_blunt_trauma_from_thrown_prop() -> void:
	var npc := _spawn_npc(Vector3.ZERO)
	await _seconds(0.5)
	var block := PropFactory.concrete_block()
	block.position = Vector3(0, 1.3, -3)
	_entities.add_child(block)
	await _frames(2)
	block.linear_velocity = Vector3(0, 1.0, 14.0)
	await _seconds(1.5)
	var fractures := 0
	for hitbox: HitboxComponent in npc.rig.hitboxes.values():
		if hitbox.is_fractured or hitbox.spinal_injury:
			fractures += 1
	print("    ", _status(npc), " hp=%.0f fractures=%d" % [npc.health.health, fractures])
	_check(npc.health.health < npc.health.max_health, "impact injured the NPC")
	_check(fractures > 0, "bones broke under blunt force (%d)" % fractures)
	_check(npc.brain.state != NPCBrain.State.IDLE, "no longer standing idle")


func _spawn_player(at: Vector3) -> Player:
	var player := Player.new()
	player.position = at
	_entities.add_child(player)
	return player


func _aim(player: Player, target: Vector3) -> void:
	player.look_at_point(target)
	await get_tree().process_frame


func test_r_firearms_through_the_player() -> void:
	var player := _spawn_player(Vector3(0, 0, 6))
	var npc := _spawn_npc(Vector3.ZERO, false, PI)
	await _seconds(0.5)
	await _aim(player, _bone(npc, Anatomy.CHEST).global_position)

	player.equip(1)
	var pistol := player.current_weapon() as Pistol
	pistol.trigger_pressed()
	_check(pistol.ammo == 16 and pistol._slide_offset > 0.0, "pistol: one round per pull, slide blows back")
	await _seconds(0.3)
	_check(pistol.ammo == 16, "pistol: semi-automatic, holding the trigger fires nothing more")
	pistol.trigger_released()
	_check(npc.vitals.wounds.size() >= 1, "pistol round wounded the target (%d wounds)" % npc.vitals.wounds.size())
	var hip := pistol.current_spread()
	pistol.secondary_pressed()
	await _seconds(0.5)
	_check(pistol.ads_amount() > 0.95 and absf(player.camera.fov - pistol.ads_fov) < 1.0 and pistol.current_spread() < hip,
		"aim down sights: fov %.0f, spread %.2f -> %.2f deg" % [player.camera.fov, hip, pistol.current_spread()])
	pistol.secondary_released()

	player.equip(3)
	var rifle := player.current_weapon() as AK47
	var pitch := player._pitch
	rifle.trigger_pressed()
	await _seconds(1.0)
	rifle.trigger_released()
	var fired := rifle.magazine_size - rifle.ammo
	_check(fired >= 9 and fired <= 11, "AK-47 cyclic rate: %d rounds in one second (~600 rpm)" % fired)
	_check(player._pitch > pitch + deg_to_rad(5.0), "recoil climbs the muzzle %.1f degrees" % rad_to_deg(player._pitch - pitch))
	rifle.reload()
	_check(rifle.is_reloading, "reload starts")
	await _seconds(rifle.reload_time + 0.1)
	_check(rifle.ammo == rifle.magazine_size and rifle.reserve_ammo == 180 - fired, "magazine refilled from the reserve")

	var target := _spawn_npc(Vector3(3, 0, 3), false, PI)
	await _seconds(0.5)
	await _aim(player, _bone(target, Anatomy.CHEST).global_position)
	player.equip(2)
	var shotgun := player.current_weapon() as Shotgun
	var before := target.health.health
	shotgun.trigger_pressed()
	shotgun.trigger_released()
	_check(shotgun.ballistics.pellets == 9 and shotgun.ammo == 5, "shotgun fires one shell of %d pellets" % shotgun.ballistics.pellets)
	_check(target.health.health < before - 30.0, "close-range pattern lands on the target (%.0f hp of trauma)" % (before - target.health.health))
	await _seconds(0.2)
	shotgun.trigger_pressed()
	shotgun.trigger_released()
	_check(shotgun.ammo == 5, "no second shot until the pump has cycled")
	await _seconds(0.5)
	shotgun.trigger_pressed()
	shotgun.trigger_released()
	_check(shotgun.ammo == 4, "fires again after the pump cycle")
	await _frames(5)
	_check(target.brain.state == NPCBrain.State.RAGDOLL or target.brain.state == NPCBrain.State.DEAD, "buckshot knocks the target down (%s)" % _status(target))


func test_s_grenade_pin_and_spoon() -> void:
	var player := _spawn_player(Vector3(0, 0, 6))
	await _seconds(0.2)
	player.equip(4)
	var grenade := player.current_weapon() as FragGrenade
	grenade.trigger_pressed()
	_check(grenade.stage == FragGrenade.Stage.PIN_PULLED, "holding fire pulls the pin")
	await _seconds(1.0)
	_check(grenade.stage == FragGrenade.Stage.PIN_PULLED, "nothing burns while the spoon is held")
	grenade.trigger_released()
	await _frames(2)
	var thrown: Array = get_children().filter(func(n: Node) -> bool: return n is GrenadeProjectile)
	_check(thrown.size() == 1, "releasing fire throws a physics grenade")
	if thrown.size() == 1:
		var projectile: GrenadeProjectile = thrown[0]
		_check(projectile.fuse_left > 3.4 and projectile.fuse_left <= 4.0, "fuse starts when the spoon flies off (%.2f s)" % projectile.fuse_left)
		_check(projectile.linear_velocity.length() > 12.0, "thrown at %.1f m/s" % projectile.linear_velocity.length())
		projectile.queue_free()
	await _seconds(grenade.draw_time + 0.2)
	_check(grenade.ammo == 1 and grenade.reserve_ammo == 6, "next grenade drawn from the reserve")
	grenade.trigger_pressed()
	grenade.secondary_pressed()
	_check(grenade.stage == FragGrenade.Stage.COOKING, "aim releases the spoon in the hand")
	await _seconds(1.5)
	grenade.trigger_released()
	await _frames(2)
	thrown = get_children().filter(func(n: Node) -> bool: return n is GrenadeProjectile)
	if thrown.size() == 1:
		var cooked: GrenadeProjectile = thrown[0]
		_check(cooked.fuse_left < 2.6 and cooked.fuse_left > 1.8, "cooked grenade keeps the rest of its fuse (%.2f s)" % cooked.fuse_left)
		cooked.queue_free()
	else:
		_check(false, "cooked grenade thrown")


func test_t_toolgun() -> void:
	var player := _spawn_player(Vector3(0, 0, 6))
	var crate := PropFactory.crate()
	crate.position = Vector3(0, 0.4, 2)
	_entities.add_child(crate)
	var other := PropFactory.crate()
	other.position = Vector3(1.6, 0.4, 2)
	_entities.add_child(other)
	await _seconds(0.5)
	var tool := player.toolgun

	# Grab: PID-tracked hold, wheel distance, freeze in place.
	await _aim(player, crate.global_position)
	tool.trigger_pressed()
	_check(tool.is_holding(), "grab picks up the crate")
	await _aim(player, Vector3(0, 2.5, 2))
	await _seconds(1.5)
	var hold_point: Vector3 = player.get_aim_transform().origin - player.get_aim_transform().basis.z * tool._hold_distance
	var grip: Vector3 = crate.global_transform * tool._held_local
	_check(grip.distance_to(hold_point) < 0.15, "held point tracks the beam (%.2f m off)" % grip.distance_to(hold_point))
	var distance := tool._hold_distance
	_check(tool.scroll(1) and tool._hold_distance > distance, "wheel pushes the held body away")
	tool.secondary_pressed()
	_check(crate.freeze and crate.freeze_mode == RigidBody3D.FREEZE_MODE_STATIC and not tool.is_holding(), "RMB freezes it in mid-air")
	var frozen_at := crate.global_position
	await _seconds(0.5)
	_check(crate.global_position.distance_to(frozen_at) < 0.001 and frozen_at.y > 1.5, "frozen crate hangs at %.2f m" % frozen_at.y)
	tool.trigger_released()

	# Freeze mode toggles it back.
	tool.set_mode(Toolgun.Mode.FREEZE)
	await _aim(player, crate.global_position)
	tool.trigger_pressed()
	_check(not crate.freeze, "freeze mode unfreezes the target")
	await _seconds(1.2)
	_check(crate.global_position.y < 0.6, "and it falls back to the floor")

	# Weld two crates.
	tool.set_mode(Toolgun.Mode.WELD)
	await _aim(player, crate.global_position)
	tool.trigger_pressed()
	await _aim(player, other.global_position)
	tool.trigger_pressed()
	var welds := _entities.get_children().filter(func(n: Node) -> bool: return n is Generic6DOFJoint3D)
	_check(welds.size() == 1, "weld creates a Generic6DOFJoint3D")
	await _frames(3)
	var offset := other.global_position - crate.global_position
	crate.apply_central_impulse(Vector3(0, 6, -5) * crate.mass)
	await _seconds(0.6)
	var drift := ((other.global_position - crate.global_position).length() - offset.length())
	_check(absf(drift) < 0.05 and other.global_position.distance_to(Vector3(1.6, 0.4, 2)) > 0.5, "welded crates move as one (separation drift %.3f m)" % drift)
	await _aim(player, crate.global_position)
	tool.secondary_pressed()
	await _frames(3)
	welds = _entities.get_children().filter(func(n: Node) -> bool: return n is Generic6DOFJoint3D)
	_check(welds.is_empty(), "RMB removes the weld")

	# Pin a crate to the world.
	tool.set_mode(Toolgun.Mode.PIN)
	await _seconds(1.0)
	await _aim(player, other.global_position)
	tool.trigger_pressed()
	await _aim(player, other.global_position + Vector3(1.5, -other.global_position.y, 0))
	tool.trigger_pressed()
	var pins := _entities.get_children().filter(func(n: Node) -> bool: return n is PinJoint3D)
	_check(pins.size() == 1, "pin creates a PinJoint3D to the world")
	if pins.size() == 1:
		var anchor: Vector3 = (pins[0] as PinJoint3D).global_position
		var reach := other.global_position.distance_to(anchor)
		other.apply_central_impulse(Vector3(0, 8, -8) * other.mass)
		await _seconds(1.0)
		_check(absf(other.global_position.distance_to(anchor) - reach) < 0.1, "pinned crate swings around its anchor (%.2f m arm)" % reach)

	# Spawn and remove.
	tool.spawn_id = &"barrel"
	tool.set_mode(Toolgun.Mode.SPAWN)
	await _aim(player, Vector3(-3, 0, 2))
	tool.trigger_pressed()
	await _frames(3)
	var barrels := _entities.get_children().filter(func(n: Node) -> bool: return n is ExplosiveBarrel)
	_check(barrels.size() == 1, "spawn mode creates the selected entity")
	if barrels.size() == 1:
		await _aim(player, (barrels[0] as Node3D).global_position)
		tool.secondary_pressed()
		await _frames(3)
		_check(not is_instance_valid(barrels[0]), "RMB deletes the target instantly")

	# Ragdoll limbs are grabbable; the NPC goes limp while held.
	var npc := _spawn_npc(Vector3(-2, 0, 1))
	await _seconds(0.5)
	tool.set_mode(Toolgun.Mode.GRAB)
	var hand := _bone(npc, &"LowerArmR")
	await _aim(player, hand.global_position)
	tool.trigger_pressed()
	_check(tool._held == hand and npc.brain.state == NPCBrain.State.RAGDOLL, "grabbing a limb ragdolls the NPC")
	await _aim(player, Vector3(-2, 3.0, 1))
	await _seconds(1.5)
	_check(hand.global_position.y > 1.6, "the body is hoisted by the arm (hand at %.2f m)" % hand.global_position.y)
	tool.trigger_released()
	tool.set_mode(Toolgun.Mode.REMOVE)
	await _aim(player, npc.hips_position())
	tool.trigger_pressed()
	await _frames(3)
	_check(not is_instance_valid(npc), "remove mode deletes the whole NPC from any bone")

	# The wheel is drawn around the centre of its control, so the control has to cover the screen.
	player._open_menu(&"spawn")
	var wheel := player.hud.radial
	_check(wheel.is_open and wheel.size.is_equal_approx(wheel.get_viewport_rect().size), "spawn wheel opens centred on the screen")
	wheel.feed(Vector2(0, -120))
	player._close_menu()
	_check(tool.spawn_id == SpawnCatalog.ITEMS[0].id and tool.mode == Toolgun.Mode.SPAWN, "releasing the key picks the highlighted entry")
	_check(SpawnCatalog.ITEMS.size() >= 10, "spawn catalogue offers %d entities" % SpawnCatalog.ITEMS.size())
	for item in SpawnCatalog.ITEMS:
		var spawned := SpawnCatalog.spawn(item.id, Vector3(randf_range(-30, 30), 0, randf_range(20, 40)), 0.0, _entities)
		if spawned == null:
			_check(false, "catalogue entry %s spawns" % item.id)
	await _seconds(0.3)
	_check(true, "every catalogue entry spawns without errors")


func test_u_main_scene_boots() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _seconds(2.0)
	var npcs := get_tree().get_nodes_in_group(Humanoid.GROUP)
	var standing := 0
	for npc: Humanoid in npcs:
		if npc.is_inside_tree() and npc.is_alive() and npc.ragdoll.hips_height() > 0.85:
			standing += 1
	_check(npcs.size() >= 9 and standing == npcs.size(), "%d of %d NPCs are standing after 2 s" % [standing, npcs.size()])
	_check(main.player.is_on_floor(), "player is on the ground")
	main.queue_free()
	await _frames(3)
