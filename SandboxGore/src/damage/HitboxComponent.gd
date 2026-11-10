class_name HitboxComponent
extends Node
## Layered anatomical hitbox for one PhysicalBone3D.
##
## A projectile crossing the part is resolved front to back through
## skin -> bone shell (skull, ribs, pelvis) -> muscle -> organs / bone core -> muscle -> shell -> skin,
## losing kinetic energy in every layer. Whatever is left exits the far side and keeps flying.
## This class is pure damage model: it emits signals and never spawns effects.

enum Region { HEAD, TORSO, ARM, LEG }

signal hit(hitbox: HitboxComponent, info: DamageInfo)
signal fractured(hitbox: HitboxComponent, spinal: bool)
signal joint_destroyed(hitbox: HitboxComponent)
signal sever_requested(hitbox: HitboxComponent, direction: Vector3)

const META_KEY := &"hitbox"
const MIN_ENERGY := 4.0             ## J; below this a projectile is spent.
const BURST_WINDOW := 0.25          ## s; trauma inside this window adds up toward dismemberment.
const BLUNT_REFERENCE_MASS := 20.0  ## kg; turns a contact impulse into an energy figure.
const BLUNT_EFFICIENCY := 0.15      ## Blunt impacts spread their load; only this share injures.
const BLUNT_MIN_ENERGY := 6.0
const MAX_HIT_VELOCITY_CHANGE := 4.0  ## m/s a single projectile may add to the bone it hits.

var part: StringName
var region := Region.TORSO
var side := 0
var skin_cost := 14.0          ## J to perforate skin with a 9 mm projectile, paid on entry and exit.
var default_thickness := 0.12

var shell_coverage := 0.0      ## Chance that the path crosses the bone shell (gaps between ribs).
var shell_thickness := 0.0
var shell_break_energy := 40.0
var shell_integrity := 1.0

var core_radius := 0.0         ## Long bone or vertebral column running along local Y.
var core_cortex := 0.0
var core_offset := Vector3.ZERO
var core_half_length := 0.0
var core_break_energy := 60.0
var core_is_spine := false
var core_integrity := 1.0

var tissue_capacity := 2500.0  ## J of soft-tissue damage that shreds the part.
var tissue_integrity := 1.0
var sever_energy := 0.0        ## J inside BURST_WINDOW that detaches the joint; 0 means never.
var sever_overpressure := 0.0  ## kPa of blast that detaches the joint; 0 means never.
var zone_top := 0.0            ## Length of the proximal end counted as the joint (knee, elbow).
var zone_bottom := 0.0         ## Same for the distal end.
var half_length := 0.2

var is_fractured := false
var spinal_injury := false
var joint_ruined := false
var is_severed := false
var detached := false          ## Part of a severed limb: no longer feeds the owner's vitals.

var organs: Array[OrganVolume3D] = []
var bone: PhysicalBone3D
var health: HealthComponent
var vitals: VitalsComponent

var _burst := 0.0
var _burst_time := 0.0
var _blunt_ready_at := 0.0


static func of(collider: Object) -> HitboxComponent:
	if collider != null and collider.has_meta(META_KEY):
		return collider.get_meta(META_KEY)
	return null


func configure(def: Dictionary) -> void:
	part = def.name
	region = def.region
	side = def.side
	var hb: Dictionary = def.hitbox
	shell_coverage = hb.get("shell_coverage", 0.0)
	shell_thickness = hb.get("shell_thickness", 0.0)
	shell_break_energy = hb.get("shell_break", 40.0)
	core_radius = hb.get("core_radius", 0.0)
	core_cortex = hb.get("core_cortex", 0.0)
	core_offset = hb.get("core_offset", Vector3.ZERO)
	core_break_energy = hb.get("core_break", 60.0)
	core_is_spine = hb.get("core_is_spine", false)
	tissue_capacity = hb.get("tissue", 2500.0)
	sever_energy = hb.get("sever_energy", 0.0)
	sever_overpressure = hb.get("sever_kpa", 0.0)
	zone_top = hb.get("zone_top", 0.0)
	zone_bottom = hb.get("zone_bottom", 0.0)
	if def.shape == "capsule":
		half_length = def.height * 0.5
		default_thickness = def.radius * 2.0
	else:
		half_length = def.size.y * 0.5
		default_thickness = def.size.z
	core_half_length = half_length


## Resolves one projectile crossing this part. `exit_point` is null when no far surface was found.
## Updates `shot.energy` and `shot.alive`.
func resolve_ballistic(space: PhysicsDirectSpaceState3D, shot: BallisticShot, entry: Vector3,
		exit_point: Variant, surface_normal: Vector3) -> void:
	var cal := shot.caliber
	var dir := shot.direction
	var energy_in := shot.energy
	var speed_in := shot.speed
	var has_exit := exit_point != null
	var chord: float = entry.distance_to(exit_point) if has_exit else default_thickness
	var flesh := BallisticMaterial.lookup(&"flesh")
	var bone_material := BallisticMaterial.lookup(&"bone")
	var skin := skin_cost * cal.area / Caliber.REFERENCE_AREA

	var shell_deposit := 0.0
	var core_deposit := 0.0
	var organ_hits: Array = []
	var e := energy_in - skin
	var stopped := e <= MIN_ENERGY

	if not stopped and shell_coverage > 0.0 and randf() < shell_coverage:
		var after := bone_material.energy_after(cal, e, shell_thickness)
		shell_deposit += e - maxf(after, 0.0)
		e = after
		shot.tumbling = true
		stopped = e <= MIN_ENERGY

	if not stopped:
		var cursor := 0.0
		for event: Array in _interior_events(space, entry, dir, chord, cal.diameter * 0.5):
			e = _through_flesh(shot, flesh, e, event[0] - cursor)
			if e <= MIN_ENERGY:
				stopped = true
				break
			var organ: OrganVolume3D = event[2]
			if organ == null:
				var after := bone_material.energy_after(cal, e, event[1])
				core_deposit += e - maxf(after, 0.0)
				e = after
				shot.tumbling = true
			else:
				var before := e
				e = _through_flesh(shot, flesh, e, event[1])
				organ_hits.append([organ, before - maxf(e, 0.0)])
			cursor = event[0] + event[1]
			if e <= MIN_ENERGY:
				stopped = true
				break
		if not stopped:
			e = _through_flesh(shot, flesh, e, chord - cursor)
			stopped = e <= MIN_ENERGY

	if not stopped and shell_coverage > 0.0 and randf() < shell_coverage:
		var after := bone_material.energy_after(cal, e, shell_thickness)
		shell_deposit += e - maxf(after, 0.0)
		e = after
		stopped = e <= MIN_ENERGY
	if not stopped:
		e -= skin
		stopped = e <= MIN_ENERGY

	var exited := has_exit and not stopped
	shot.energy = maxf(e, 0.0) if exited else 0.0
	shot.alive = exited
	var deposited := energy_in - shot.energy

	if bone != null:
		# Capped per hit: a light limb must not be launched by an exaggerated bullet impulse,
		# least of all once it has been shot off and no body is left to share the momentum.
		var momentum := minf(cal.mass * (speed_in - shot.speed) * cal.impulse_scale, bone.mass * MAX_HIT_VELOCITY_CHANGE)
		bone.apply_impulse(dir * momentum * (0.1 if detached else 1.0), entry - bone.global_position)

	var info := DamageInfo.make(shot.damage_type, entry, dir, shot.live_attacker())
	info.energy = deposited
	info.amount = deposited * 0.04
	info.normal = surface_normal
	info.caliber = cal
	info.part = part
	info.exited = exited
	info.tumbling = shot.tumbling
	info.bone_hit = shell_deposit + core_deposit > 0.0
	if exited:
		info.exit_position = exit_point

	tissue_integrity = maxf(tissue_integrity - (deposited - shell_deposit - core_deposit) / tissue_capacity, 0.0)
	for organ_hit: Array in organ_hits:
		var organ: OrganVolume3D = organ_hit[0]
		info.organs.append(organ.organ_name)
		organ.apply_trauma(organ_hit[1], true, entry, surface_normal)
	_damage_shell(shell_deposit)
	_damage_core(core_deposit)
	_check_joint_zone(entry, deposited)
	_add_surface_wounds(info, deposited)
	if vitals != null and not detached:
		vitals.add_pain(deposited / 900.0 + (0.25 if info.bone_hit else 0.0))
	if health != null:
		health.apply_damage(info)
	hit.emit(self, info)
	_accumulate_burst(deposited, dir)


## Blunt trauma from a contact impulse (falls, thrown props, vehicles).
func apply_blunt(impulse: float, position: Vector3, normal: Vector3, attacker: Node = null) -> void:
	var now := Layers.physics_time()
	var energy := BLUNT_EFFICIENCY * impulse * impulse / BLUNT_REFERENCE_MASS
	if energy < BLUNT_MIN_ENERGY or now < _blunt_ready_at:
		return
	_blunt_ready_at = now + 0.05
	var info := DamageInfo.make(DamageInfo.Type.BLUNT, position, -normal, attacker)
	info.energy = energy
	info.amount = energy * 0.05
	info.normal = normal
	info.part = part
	if vitals != null and not detached:
		vitals.add_pain(energy / 300.0)
		if region == Region.HEAD:
			if energy > 20.0:
				vitals.knock_out(minf(energy / 5.0, 15.0))
			else:
				vitals.stun(1.0 + energy / 6.0)
	# The skeleton takes the load first; whatever exceeds it reaches the organs behind.
	if shell_coverage > 0.0:
		_damage_shell(energy)
	else:
		_damage_core(energy)
	var overflow := energy - (shell_break_energy if shell_coverage > 0.0 else core_break_energy)
	if overflow > 0.0:
		for organ in organs:
			organ.apply_trauma(overflow * 0.15, false, position, normal)
		info.bone_hit = true
	if energy > 120.0 and vitals != null and not detached:
		vitals.add_wound(Wound.create(bone, position, normal, clampf(energy / 80.0, 1.0, 6.0), false, 30.0, &"laceration"))
	if health != null:
		health.apply_damage(info)
	hit.emit(self, info)
	_accumulate_burst(energy * 0.5, -normal)


## Blast wave. `impulse` is the momentum already scaled for this bone's mass.
func apply_blast(overpressure: float, impulse: Vector3, origin: Vector3, attacker: Node = null) -> void:
	if bone != null:
		bone.apply_central_impulse(impulse)
	var position := bone.global_position if bone != null else origin
	var info := DamageInfo.make(DamageInfo.Type.BLAST, position, (position - origin).normalized(), attacker)
	info.overpressure = overpressure
	info.impulse = impulse
	# Every bone reports the same wave, so each contributes in proportion to its mass.
	info.amount = overpressure * 0.3 * (bone.mass if bone != null else 5.0) / 20.0
	info.part = part
	if vitals != null and not detached:
		vitals.add_pain(overpressure / 150.0)
		if overpressure > 35.0:
			vitals.stun(2.0 + overpressure / 20.0)
		if region == Region.HEAD and overpressure > 60.0:
			vitals.knock_out(minf(overpressure / 8.0, 20.0))
	if overpressure > 100.0:
		# Primary blast injury: air-filled organs fail first.
		for organ in organs:
			if organ.kind == OrganVolume3D.Kind.LUNG:
				organ.apply_trauma((overpressure - 100.0) * 0.6, false, position, info.direction)
	if overpressure > 150.0:
		var load_energy := (overpressure - 150.0) * 0.5
		if shell_coverage > 0.0:
			_damage_shell(load_energy)
		_damage_core(load_energy)
	if health != null:
		health.apply_damage(info)
	hit.emit(self, info)
	if sever_overpressure > 0.0 and not is_severed and overpressure >= sever_overpressure * randf_range(0.8, 1.3):
		sever_requested.emit(self, info.direction)


func _through_flesh(shot: BallisticShot, flesh: BallisticMaterial, e: float, length: float) -> float:
	if length <= 0.0 or e <= 0.0:
		return e
	var cal := shot.caliber
	var remaining := length
	if not shot.tumbling:
		var stable := minf(remaining, maxf(cal.yaw_depth - shot.flesh_depth, 0.0))
		e = flesh.energy_after(cal, e, stable, cal.flesh_drag_stable)
		shot.flesh_depth += stable
		remaining -= stable
		if shot.flesh_depth >= cal.yaw_depth:
			shot.tumbling = true
	if remaining > 0.0 and e > 0.0:
		e = flesh.energy_after(cal, e, remaining, cal.flesh_drag_tumbling)
		shot.flesh_depth += remaining
	return e


## Returns [distance_from_entry, thickness, organ_or_null] sorted along the path.
## Organs come from a ray query on the organ layer; the bone core is solved analytically.
func _interior_events(space: PhysicsDirectSpaceState3D, entry: Vector3, dir: Vector3, chord: float, bullet_radius: float) -> Array:
	var events: Array = []
	if not organs.is_empty():
		var query := PhysicsRayQueryParameters3D.create(entry, entry + dir * chord, Layers.ORGANS)
		query.collide_with_areas = true
		query.collide_with_bodies = false
		var exclude: Array[RID] = []
		for i in 6:
			query.exclude = exclude
			var result := space.intersect_ray(query)
			if result.is_empty():
				break
			exclude.append(result.rid)
			var organ := result.collider as OrganVolume3D
			if organ != null and organ.hitbox == self:
				events.append([entry.distance_to(result.position), minf(organ.path_length, chord), organ])
	if core_radius > 0.0 and bone != null:
		var inverse := bone.global_transform.affine_inverse()
		var p0 := inverse * entry
		var p1 := inverse * (entry + dir * chord)
		var top := core_offset + Vector3(0.0, core_half_length, 0.0)
		var bottom := core_offset - Vector3(0.0, core_half_length, 0.0)
		var closest := Geometry3D.get_closest_points_between_segments(p0, p1, top, bottom)
		var gap := closest[0].distance_to(closest[1])
		var reach := core_radius + bullet_radius
		if gap < reach:
			var through := minf(2.0 * sqrt(reach * reach - gap * gap), 2.0 * core_cortex)
			events.append([maxf(p0.distance_to(closest[0]) - through * 0.5, 0.0), through, null])
	events.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return events


func _damage_shell(energy: float) -> void:
	if energy <= 0.0 or shell_integrity <= 0.0:
		return
	shell_integrity -= energy / shell_break_energy
	if shell_integrity <= 0.0:
		is_fractured = true
		fractured.emit(self, false)


func _damage_core(energy: float) -> void:
	if energy <= 0.0 or core_radius <= 0.0 or core_integrity <= 0.0:
		return
	core_integrity -= energy / core_break_energy
	if core_integrity <= 0.0:
		if core_is_spine:
			spinal_injury = true
		else:
			is_fractured = true
		fractured.emit(self, core_is_spine)


func _check_joint_zone(entry: Vector3, deposited: float) -> void:
	if joint_ruined or bone == null or deposited < 40.0:
		return
	var y := (bone.global_transform.affine_inverse() * entry).y
	if (zone_top > 0.0 and y > half_length - zone_top) or (zone_bottom > 0.0 and y < zone_bottom - half_length):
		joint_ruined = true
		joint_destroyed.emit(self)


func _add_surface_wounds(info: DamageInfo, deposited: float) -> void:
	if vitals == null or detached or bone == null:
		return
	vitals.add_wound(Wound.create(bone, info.position, info.normal, clampf(1.0 + deposited * 0.004, 1.0, 6.0)))
	if info.exited:
		# A tumbling bullet leaves a much larger exit wound than its entry.
		var rate := clampf(2.0 + deposited * 0.009, 2.0, 16.0) * (1.6 if info.tumbling else 1.0)
		vitals.add_wound(Wound.create(bone, info.exit_position, info.direction, rate, false, 35.0, &"exit wound"))


func _accumulate_burst(energy: float, direction: Vector3) -> void:
	var now := Layers.physics_time()
	_burst = _burst * exp(-(now - _burst_time) / BURST_WINDOW) + energy
	_burst_time = now
	if sever_energy <= 0.0 or is_severed:
		return
	if _burst >= sever_energy or (is_fractured and tissue_integrity <= 0.0):
		sever_requested.emit(self, direction)
