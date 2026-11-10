class_name Anatomy
extends RefCounted
## Data table for the humanoid: skeleton layout, collision shapes, joint limits, motor gains,
## layered hitbox parameters and organ volumes. HumanoidRig turns it into nodes.
##
## Model space: feet on the origin, +Y up, facing -Z, right hand on +X. Every bone frame is
## axis-aligned at rest, so a positive rotation about X swings a hanging limb forward.

const HIPS := &"Hips"
const SPINE := &"Spine"
const CHEST := &"Chest"
const HEAD := &"Head"
const LEFT := -1
const RIGHT := 1
const STAND_HEIGHT := 1.0  ## Height of the hips body centre above the ground when standing.


static func limb(base: String, side: int) -> StringName:
	return StringName(base + ("L" if side < 0 else "R"))


## Parts are returned parent-first. Angular limits are true right-handed angles in degrees.
static func humanoid() -> Array[Dictionary]:
	var torso := HitboxComponent.Region.TORSO
	var parts: Array[Dictionary] = []

	parts.append({
		"name": HIPS, "parent": &"", "joint": Vector3(0, 0.96, 0), "center": Vector3(0, 0.04, 0),
		"shape": "box", "size": Vector3(0.32, 0.20, 0.20), "mass": 11.0,
		"lim_min": Vector3.ZERO, "lim_max": Vector3.ZERO, "kp": 0.0, "kd": 0.0, "torque": 0.0,
		"look": "pants", "region": torso, "side": 0, "stump": 0.09,
		"hitbox": {"shell_coverage": 0.7, "shell_thickness": 0.008, "shell_break": 90.0, "tissue": 4000.0},
		"organs": [],
	})
	parts.append({
		"name": SPINE, "parent": HIPS, "joint": Vector3(0, 1.08, 0), "center": Vector3(0, 0.09, 0),
		"shape": "box", "size": Vector3(0.29, 0.20, 0.19), "mass": 10.0,
		"lim_min": Vector3(-35, -20, -20), "lim_max": Vector3(20, 20, 20), "kp": 4000.0, "kd": 130.0, "torque": 500.0,
		"look": "shirt", "region": torso, "side": 0, "stump": 0.09,
		"hitbox": {"core_radius": 0.022, "core_cortex": 0.02, "core_offset": Vector3(0, 0, 0.065), "core_break": 60.0,
			"core_is_spine": true, "tissue": 4000.0},
		"organs": [
			{"name": &"Liver", "kind": OrganVolume3D.Kind.LIVER, "radius": 0.065, "height": 0.0, "pos": Vector3(0.065, 0.035, -0.015),
				"toughness": 150.0, "bleed": 45.0, "arterial": false, "path": 0.12},
		],
	})
	parts.append({
		"name": CHEST, "parent": SPINE, "joint": Vector3(0, 1.28, 0), "center": Vector3(0, 0.12, 0),
		"shape": "box", "size": Vector3(0.36, 0.26, 0.22), "mass": 17.0,
		"lim_min": Vector3(-25, -25, -15), "lim_max": Vector3(15, 25, 15), "kp": 3000.0, "kd": 110.0, "torque": 400.0,
		"look": "shirt", "region": torso, "side": 0, "stump": 0.1,
		"hitbox": {"shell_coverage": 0.6, "shell_thickness": 0.004, "shell_break": 30.0, "core_radius": 0.022,
			"core_cortex": 0.02, "core_offset": Vector3(0, 0, 0.075), "core_break": 60.0, "core_is_spine": true, "tissue": 5000.0},
		"organs": [
			{"name": &"Heart", "kind": OrganVolume3D.Kind.HEART, "radius": 0.05, "height": 0.0, "pos": Vector3(-0.025, 0.0, -0.02),
				"toughness": 60.0, "bleed": 220.0, "arterial": true, "path": 0.09},
			{"name": &"LungL", "kind": OrganVolume3D.Kind.LUNG, "lung_index": 0, "radius": 0.06, "height": 0.2, "pos": Vector3(-0.1, 0.01, 0.005),
				"toughness": 120.0, "bleed": 12.0, "arterial": false, "path": 0.11},
			{"name": &"LungR", "kind": OrganVolume3D.Kind.LUNG, "lung_index": 1, "radius": 0.06, "height": 0.2, "pos": Vector3(0.1, 0.01, 0.005),
				"toughness": 120.0, "bleed": 12.0, "arterial": false, "path": 0.11},
		],
	})
	parts.append({
		"name": HEAD, "parent": CHEST, "joint": Vector3(0, 1.54, 0), "center": Vector3(0, 0.125, 0),
		"shape": "capsule", "radius": 0.1, "height": 0.27, "mass": 5.5,
		"lim_min": Vector3(-40, -60, -30), "lim_max": Vector3(40, 60, 30), "kp": 1200.0, "kd": 70.0, "torque": 60.0,
		"look": "skin", "region": HitboxComponent.Region.HEAD, "side": 0, "stump": 0.05,
		"hitbox": {"shell_coverage": 1.0, "shell_thickness": 0.007, "shell_break": 45.0, "tissue": 1500.0,
			"sever_energy": 2100.0, "sever_kpa": 260.0},
		"organs": [
			{"name": &"Brain", "kind": OrganVolume3D.Kind.BRAIN, "radius": 0.07, "height": 0.0, "pos": Vector3(0, 0.055, 0),
				"toughness": 25.0, "bleed": 0.0, "arterial": false, "path": 0.13},
			{"name": &"CarotidL", "kind": OrganVolume3D.Kind.ARTERY, "radius": 0.016, "height": 0.07, "pos": Vector3(-0.032, -0.105, -0.015),
				"toughness": 12.0, "bleed": 70.0, "arterial": true, "path": 0.02},
			{"name": &"CarotidR", "kind": OrganVolume3D.Kind.ARTERY, "radius": 0.016, "height": 0.07, "pos": Vector3(0.032, -0.105, -0.015),
				"toughness": 12.0, "bleed": 70.0, "arterial": true, "path": 0.02},
		],
	})

	for side: int in [LEFT, RIGHT]:
		var x := 0.225 * side
		parts.append(_mirror({
			"name": limb("UpperArm", side), "parent": CHEST, "joint": Vector3(x, 1.47, 0), "center": Vector3(0, -0.14, 0),
			"shape": "capsule", "radius": 0.047, "height": 0.33, "mass": 2.2,
			"lim_min": Vector3(-50, -60, -20), "lim_max": Vector3(170, 60, 100), "kp": 350.0, "kd": 32.0, "torque": 120.0,
			"look": "shirt", "region": HitboxComponent.Region.ARM, "side": side, "stump": 0.047,
			"hitbox": {"core_radius": 0.011, "core_cortex": 0.008, "core_break": 50.0, "tissue": 1600.0,
				"sever_energy": 1000.0, "sever_kpa": 220.0, "zone_bottom": 0.07},
			"organs": [
				{"name": limb("Brachial", side), "kind": OrganVolume3D.Kind.ARTERY, "radius": 0.013, "height": 0.26,
					"pos": Vector3(-0.02 * side, 0, -0.008), "toughness": 12.0, "bleed": 30.0, "arterial": true, "path": 0.02},
			],
		}, side))
		parts.append(_mirror({
			"name": limb("LowerArm", side), "parent": limb("UpperArm", side), "joint": Vector3(x, 1.19, 0), "center": Vector3(0, -0.15, 0),
			"shape": "capsule", "radius": 0.04, "height": 0.34, "mass": 1.7,
			"lim_min": Vector3(0, -30, 0), "lim_max": Vector3(145, 30, 0), "kp": 300.0, "kd": 28.0, "torque": 70.0,
			"look": "skin", "region": HitboxComponent.Region.ARM, "side": side, "stump": 0.04,
			"hitbox": {"core_radius": 0.01, "core_cortex": 0.007, "core_break": 38.0, "tissue": 1200.0,
				"sever_energy": 700.0, "sever_kpa": 180.0, "zone_top": 0.08},
			"organs": [],
		}, side))

	for side: int in [LEFT, RIGHT]:
		var x := 0.095 * side
		parts.append(_mirror({
			"name": limb("UpperLeg", side), "parent": HIPS, "joint": Vector3(x, 0.93, 0), "center": Vector3(0, -0.21, 0),
			"shape": "capsule", "radius": 0.075, "height": 0.46, "mass": 7.5,
			"lim_min": Vector3(-25, -30, -15), "lim_max": Vector3(120, 30, 45), "kp": 450.0, "kd": 38.0, "torque": 450.0,
			"look": "pants", "region": HitboxComponent.Region.LEG, "side": side, "stump": 0.075,
			"hitbox": {"core_radius": 0.014, "core_cortex": 0.012, "core_break": 75.0, "tissue": 2600.0,
				"sever_energy": 1700.0, "sever_kpa": 300.0, "zone_bottom": 0.1},
			"organs": [
				{"name": limb("Femoral", side), "kind": OrganVolume3D.Kind.ARTERY, "radius": 0.017, "height": 0.36,
					"pos": Vector3(-0.028 * side, 0, -0.015), "toughness": 15.0, "bleed": 55.0, "arterial": true, "path": 0.025},
			],
		}, side))
		parts.append(_mirror({
			"name": limb("LowerLeg", side), "parent": limb("UpperLeg", side), "joint": Vector3(x, 0.5, 0), "center": Vector3(0, -0.2, 0),
			"shape": "capsule", "radius": 0.052, "height": 0.44, "mass": 3.4,
			"lim_min": Vector3(-140, -5, -5), "lim_max": Vector3(0, 5, 5), "kp": 400.0, "kd": 34.0, "torque": 300.0,
			"look": "pants", "region": HitboxComponent.Region.LEG, "side": side, "stump": 0.052,
			"hitbox": {"core_radius": 0.012, "core_cortex": 0.01, "core_break": 55.0, "tissue": 1800.0,
				"sever_energy": 1100.0, "sever_kpa": 230.0, "zone_top": 0.12},
			"organs": [],
		}, side))
		parts.append(_mirror({
			"name": limb("Foot", side), "parent": limb("LowerLeg", side), "joint": Vector3(x, 0.085, 0), "center": Vector3(0, -0.045, -0.06),
			"shape": "box", "size": Vector3(0.095, 0.08, 0.25), "mass": 1.0,
			"lim_min": Vector3(-40, -10, -15), "lim_max": Vector3(25, 10, 15), "kp": 600.0, "kd": 45.0, "torque": 30.0,
			"look": "shoes", "region": HitboxComponent.Region.LEG, "side": side, "stump": 0.04,
			"hitbox": {"core_radius": 0.02, "core_cortex": 0.008, "core_break": 30.0, "tissue": 800.0,
				"sever_energy": 500.0, "sever_kpa": 160.0},
			"organs": [],
		}, side))
	return parts


## Limits are authored for the right side; the left side mirrors twist and abduction.
static func _mirror(part: Dictionary, side: int) -> Dictionary:
	if side < 0:
		var lo: Vector3 = part.lim_min
		var hi: Vector3 = part.lim_max
		part.lim_min = Vector3(lo.x, -hi.y, -hi.z)
		part.lim_max = Vector3(hi.x, -lo.y, -lo.z)
	return part
