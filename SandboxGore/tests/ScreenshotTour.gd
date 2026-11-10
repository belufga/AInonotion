extends Node3D
## Scripted visual tour of the main scene. Renders a set of screenshots for review.
## Run: godot --path . --fixed-fps 60 res://tests/ScreenshotTour.tscn -- /output/dir
## Rendering is switched off between shots, so the tour is quick even on a software renderer.

var _main: Node3D
var _player: Player
var _dir := "/tmp/shots"
var _index := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_dir = args[0]
	DirAccess.make_dir_recursive_absolute(_dir)
	seed(7)
	_main = (load("res://main.tscn") as PackedScene).instantiate()
	add_child(_main)
	_player = _main.player
	await _wait(1.5)

	_place(Vector3(0, 0.05, 9), Vector3(0, 1.1, -10))
	await _shot("overview")

	# Rifle burst into a target standing in front of the backstop.
	var target := _spawn(&"civilian", Vector3(2.0, 0, -22.4))
	_place(Vector3(2.0, 0.05, -18.0), Vector3(2.0, 1.3, -22.4))
	_player.equip(3)
	await _wait(1.2)
	_player.look_at_point(target.rig.bones[Anatomy.CHEST].global_position)
	await _wait(0.05)
	_player.current_weapon().trigger_pressed()
	await _wait(0.32)
	_player.current_weapon().trigger_released()
	_player.look_at_point(Vector3(2.0, 1.2, -22.4))
	await _shot("rifle_burst", 6)
	await _wait(3.0)
	_player.look_at_point(Vector3(2.0, 0.5, -22.4))
	await _shot("rifle_aftermath")

	# Point-blank buckshot on a forearm, then a close look at the stump.
	var victim := _spawn(&"civilian", Vector3(-3.0, 0, -20.0))
	_place(Vector3(-3.225, 0.05, -19.45), Vector3(-3.0, 1.2, -20.0))
	_player.equip(2)
	await _wait(1.2)
	var shotgun := _player.current_weapon() as Shotgun
	var forearm: HitboxComponent = victim.rig.hitboxes[&"LowerArmL"]
	# The pattern is random, so keep firing until the limb is off, as a player would.
	for shell in 4:
		_player.look_at_point(victim.rig.bones[&"LowerArmL"].global_position)
		await _wait(0.05)
		shotgun.trigger_pressed()
		shotgun.trigger_released()
		if forearm.is_severed:
			break
		await _wait(shotgun.pump_time + 0.1)
	if not forearm.is_severed:
		print("forearm survived four shells; the next two shots will not show a stump")
	await _shot("shotgun_dismember", 8)
	await _wait(2.0)
	_player.equip(0)
	_player.noclip = true
	# Look straight into the cut: the cap sits on the elbow end of the upper arm.
	var upper_arm: PhysicalBone3D = victim.rig.bones[&"UpperArmL"]
	var stump := upper_arm.global_position
	var outward := Vector3.UP
	for child in upper_arm.get_children():
		var cap := child as StumpCap
		if cap != null and cap.global_position.distance_to(stump) > 0.02:
			outward = (cap.global_position - stump).normalized()
			stump = cap.global_position
	var viewpoint := stump + outward * 0.45 + Vector3.UP * 0.12
	viewpoint.y = maxf(viewpoint.y, 0.15)
	_place(viewpoint - Vector3.UP * Player.EYE_HEIGHT, stump)
	await _shot("stump_cap")
	_player.noclip = false

	# Femoral artery: pulsed spurts, pooling and the vitals inspector.
	var bleeder := _spawn(&"civilian", Vector3(-8.0, 0, -19.0))
	_place(Vector3(-8.0, 0.05, -15.0), Vector3(-8.0, 1.0, -19.0))
	_player.equip(1)
	await _wait(1.2)
	for organ: OrganVolume3D in bleeder.rig.organs:
		if organ.organ_name == &"FemoralL":
			var eye := _player.get_aim_transform().origin
			Ballistics.fire(BallisticShot.create(Caliber.parabellum_9mm(), eye, organ.global_position - eye, _player), 40.0)
	await _wait(7.0)
	_player.look_at_point(bleeder.hips_position())
	await _shot("arterial_bleed", 10)
	await _wait(40.0)
	_player.look_at_point(bleeder.hips_position())
	await _shot("hemorrhagic_shock", 12)

	# Grenade among three NPCs.
	for spot: Vector3 in [Vector3(7.2, 0, -19.4), Vector3(8.6, 0, -20.6), Vector3(9.4, 0, -18.4)]:
		_spawn(&"civilian", spot)
	_place(Vector3(8.0, 0.05, -12.5), Vector3(8.2, 0.8, -19.5))
	_player.equip(4)
	await _wait(1.0)
	var grenade := GrenadeProjectile.create(_player)
	_main.entities.add_child(grenade)
	grenade.global_position = Vector3(8.0, 0.1, -19.6)
	grenade.release_spoon(0.25)
	await _wait(0.2)
	while is_instance_valid(grenade) and not grenade.exploded:
		await get_tree().process_frame
	await _shot("explosion", 3)
	await _wait(3.0)
	_player.look_at_point(Vector3(8.2, 0.3, -19.5))
	await _shot("gib_aftermath")

	# Toolgun: physgun beam holding a crate, then both radial wheels.
	_player.equip(0)
	_player.toolgun.set_mode(Toolgun.Mode.GRAB)
	_place(Vector3(-1.0, 0.05, 7.0), Vector3(-3.0, 0.4, 3.0))
	await _wait(0.8)
	_player.toolgun.trigger_pressed()
	_player.look_at_point(Vector3(-3.0, 2.6, 2.0))
	await _wait(1.5)
	await _shot("physgun_grab", 6)
	_player.toolgun.secondary_pressed()
	_player.toolgun.trigger_released()
	_player._open_menu(&"spawn")
	_player.hud.radial.feed(Vector2(150, -90))
	await _shot("radial_spawn")
	_player._close_menu()
	_player._open_menu(&"tool")
	_player.hud.radial.feed(Vector2(-140, 60))
	await _shot("radial_tool")
	_player._close_menu()

	# Pistol aimed down its sights at a distant head.
	_place(Vector3(0, 0.05, 2.0), Vector3(-1.2, 1.7, -11.5))
	_player.equip(1)
	_player.current_weapon().secondary_pressed()
	await _wait(1.0)
	var heads := get_tree().get_nodes_in_group(Humanoid.GROUP).filter(func(n: Humanoid) -> bool: return n.is_alive() and n.hips_position().z > -13.0 and absf(n.hips_position().x) < 5.0)
	if not heads.is_empty():
		_player.look_at_point((heads[0] as Humanoid).rig.bones[Anatomy.HEAD].global_position)
	await _shot("pistol_ads")
	get_tree().quit()


func _spawn(id: StringName, at: Vector3) -> Humanoid:
	var npc := SpawnCatalog.spawn(id, at, 0.0, _main.entities) as Humanoid
	npc.brain.wanders = false
	return npc


func _place(position: Vector3, look: Vector3) -> void:
	_player.global_position = position
	_player.velocity = Vector3.ZERO
	_player.look_at_point(look)


func _wait(seconds: float) -> void:
	RenderingServer.render_loop_enabled = false
	for i in int(seconds * 60.0):
		await get_tree().physics_frame
	RenderingServer.render_loop_enabled = true


func _shot(label: String, frames := 4) -> void:
	RenderingServer.render_loop_enabled = true
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_index += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [_dir, _index, label])
	print("saved %02d_%s" % [_index, label])
