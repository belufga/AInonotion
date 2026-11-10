class_name GoreComponent
extends Node
## Presentation and dismemberment layer for one humanoid.
##
## Listens to the damage model and turns it into wound decals, blood bursts, heartbeat-synchronised
## arterial spurts, drips and growing pools. Also performs limb severing (joint release, stump
## caps, stump haemorrhage) and whole-body gibbing.

signal part_severed(part: StringName)
signal gibbed

const DRIP_INTERVAL := 0.2
const DRIP_VOLUME := 10.0       ## ml a wound must lose before it marks the floor again.
const MAX_SPURTS_PER_BEAT := 3
const MAX_SEVER_SPEED := 3.0    ## m/s a limb may be moving relative to the body when it comes off.

var rig: HumanoidRig
var vitals: VitalsComponent
var is_gibbed := false

var _drip_timer := 0.0
var _stump_drips: Array[Wound] = []  ## Severed limbs keep dribbling without touching the owner's vitals.


func setup(p_rig: HumanoidRig, p_vitals: VitalsComponent) -> void:
	rig = p_rig
	vitals = p_vitals
	for hitbox: HitboxComponent in rig.hitboxes.values():
		hitbox.hit.connect(_on_hit)
		hitbox.sever_requested.connect(_on_sever_requested)
	vitals.heartbeat.connect(_on_heartbeat)
	vitals.coughed_blood.connect(_on_coughed_blood)


func _physics_process(delta: float) -> void:
	_drip_timer += delta
	if _drip_timer < DRIP_INTERVAL:
		return
	_drip_timer = 0.0
	for wound in vitals.wounds:
		if wound.pending >= DRIP_VOLUME and wound.is_valid():
			BloodFX.drip(wound.get_instance_id(), wound.world_position(), wound.pending)
			wound.pending = 0.0
	var i := _stump_drips.size() - 1
	while i >= 0:
		var wound := _stump_drips[i]
		if not wound.is_valid() or wound.rate <= 0.0:
			_stump_drips.remove_at(i)
		else:
			var amount := minf(wound.rate, 14.0)
			wound.rate -= amount
			BloodFX.drip(wound.get_instance_id(), wound.world_position(), amount)
		i -= 1


## Detaches `part` and everything below it from the body. Returns false if it cannot be severed.
func sever(part: StringName, direction := Vector3.ZERO) -> bool:
	if rig == null or not rig.hitboxes.has(part):
		return false
	var hitbox := rig.hitboxes[part]
	var def := rig.defs[part]
	if hitbox.is_severed or def.parent == &"":
		return false
	var child := rig.bones[part]
	var parent := rig.bones[def.parent]
	var parent_hitbox := rig.hitboxes[def.parent]
	var joint := rig.joint_position(part)
	var outward := (child.global_position - joint).normalized()

	hitbox.is_severed = true
	rig.detach(part)
	for sub_part in rig.subtree(part):
		rig.hitboxes[sub_part].detached = true

	var parent_cap := joint + outward * rig.cap_offset_parent(part)
	var child_cap := joint - outward * rig.cap_offset_child(part)
	StumpCap.attach(parent, parent_cap, outward, def.stump)
	StumpCap.attach(child, child_cap, -outward, def.stump)

	# Hits that landed before the joint let go must not turn the limb into a missile.
	var child_state := PhysicsServer3D.body_get_direct_state(child.get_rid())
	var parent_state := PhysicsServer3D.body_get_direct_state(parent.get_rid())
	if child_state != null and parent_state != null:
		var relative := child_state.linear_velocity - parent_state.linear_velocity
		child_state.linear_velocity = parent_state.linear_velocity + relative.limit_length(MAX_SEVER_SPEED)
	var scatter := Vector3(randf() - 0.5, randf() * 0.5, randf() - 0.5)
	child.apply_central_impulse((outward * 1.5 + direction * 1.5 + scatter * 0.8) * child.mass)

	if not parent_hitbox.detached:
		# The stump is an open artery: it bleeds hard and pulses until pressure is gone.
		var rate: float = def.stump * (2000.0 if part == Anatomy.HEAD else 800.0)
		vitals.add_wound(Wound.create(parent, parent_cap, outward, rate, true, 0.0, &"stump"))
		vitals.add_pain(0.6)
	_stump_drips.append(Wound.create(child, child_cap, -outward, 250.0, false, 0.0, &"severed"))

	BloodFX.blood_burst(joint, outward, 5.0, 1.0, 45.0)
	BloodFX.blood_burst(joint, -outward, 4.0, 0.7, 45.0)
	BloodFX.gibs.burst(joint, outward + direction, 3, 3.5, 0.7, 0.4)
	part_severed.emit(part)
	return true


## Epicentre trauma: every limb comes off and the torso is reduced to giblets.
func gib(origin: Vector3, strength := 1.0) -> void:
	if is_gibbed or rig == null:
		return
	is_gibbed = true
	vitals.kill("blast trauma")
	var torso := HitboxComponent.Region.TORSO
	for part in rig.order:
		var def := rig.defs[part]
		if def.parent == &"" or def.region == torso:
			continue
		# Limbs must leave the torso; elbows, knees and ankles only sometimes let go.
		var attached_to_torso: bool = rig.defs[def.parent].region == torso
		if attached_to_torso or randf() < 0.6:
			var bone := rig.bones[part]
			var away := (bone.global_position - origin).normalized()
			sever(part, away * 3.0 * strength)
	for part: StringName in [Anatomy.HIPS, Anatomy.SPINE, Anatomy.CHEST]:
		var position := rig.bones[part].global_position
		var away := (position - origin).normalized() + Vector3.UP * 0.6
		BloodFX.gibs.burst(position, away, 6, 7.0 * strength, 1.0, 0.3)
		BloodFX.blood_burst(position, away, 8.0, 1.0, 70.0)
		rig.destroy_part(part)
	var center := rig.bones[Anatomy.CHEST].global_position
	for i in 7:
		var fling := Vector3(randf() - 0.5, randf() * 0.6, randf() - 0.5).normalized() * randf_range(3.0, 7.0)
		BloodFX.fling(center, fling, randf_range(0.5, 1.1))
	gibbed.emit()


func _on_sever_requested(hitbox: HitboxComponent, direction: Vector3) -> void:
	sever(hitbox.part, direction)


func _on_hit(hitbox: HitboxComponent, info: DamageInfo) -> void:
	if hitbox.bone == null:
		return
	match info.type:
		DamageInfo.Type.BALLISTIC, DamageInfo.Type.SHRAPNEL:
			var size := clampf(0.04 + info.energy / 9000.0, 0.04, 0.12)
			BloodFX.wound_mark(hitbox.bone, info.position, info.normal, size)
			BloodFX.blood_burst(info.position, info.normal, 2.5, clampf(info.energy / 1500.0, 0.15, 0.6), 30.0)
			if info.exited:
				# Exit wounds are larger than entries, far more so once the bullet has tumbled.
				var expansion := 2.2 if info.tumbling else 1.3
				BloodFX.wound_mark(hitbox.bone, info.exit_position, info.direction, size * expansion)
				BloodFX.blood_burst(info.exit_position, info.direction, 3.0 + info.energy / 250.0, clampf(info.energy / 900.0, 0.2, 1.0), 16.0)
				BloodFX.project_splatter(info.exit_position, info.direction, 4.5, clampf(0.25 + info.energy / 1200.0, 0.25, 1.4))
				if info.energy > 650.0:
					BloodFX.gibs.burst(info.exit_position, info.direction, 1 + int(info.energy / 900.0), 4.0, 0.5)
		DamageInfo.Type.BLUNT:
			if info.energy > 60.0:
				BloodFX.blood_burst(info.position, info.normal, 2.0, 0.3, 50.0)
				BloodFX.fling(info.position, info.normal * 1.5, clampf(info.energy / 400.0, 0.15, 0.6))


func _on_heartbeat(systolic: float) -> void:
	var count := 0
	for wound in vitals.wounds:
		if wound.arterial and wound.flow > 2.0 and wound.is_valid():
			var normal := wound.world_normal()
			var jitter := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.25
			BloodFX.arterial_spurt(wound.world_position() + normal * 0.02, (normal + Vector3.UP * 0.25 + jitter).normalized(), systolic)
			count += 1
			if count >= MAX_SPURTS_PER_BEAT:
				return


func _on_coughed_blood() -> void:
	var head := rig.bones[Anatomy.HEAD]
	if rig.hitboxes[Anatomy.HEAD].detached:
		return
	var mouth := head.global_transform * Vector3(0.0, -0.03, -0.1)
	var forward := -head.global_basis.z
	BloodFX.blood_burst(mouth, forward + Vector3.DOWN * 0.3, 2.2, 0.3, 28.0)
	BloodFX.fling(mouth, forward * 1.8, 0.14)
