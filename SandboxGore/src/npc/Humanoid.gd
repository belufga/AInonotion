class_name Humanoid
extends Node3D
## NPC entity root. Composes the components and routes events between them:
## HealthComponent, VitalsComponent, HumanoidRig (bones, hitboxes, organs), ActiveRagdoll,
## ProceduralAnimator, GoreComponent and NPCBrain.
##
## Set the transform before adding the node to the tree; the ragdoll is built where it spawns.

const GROUP := &"npc"

@export var armed := false
@export var wanders := true

var health: HealthComponent
var vitals: VitalsComponent
var rig: HumanoidRig
var ragdoll: ActiveRagdoll
var animator: ProceduralAnimator
var gore: GoreComponent
var brain: NPCBrain
var weapon_model: Node3D

var _weapon_side := Anatomy.RIGHT


func _ready() -> void:
	add_to_group(Layers.GROUP_ENTITY)
	add_to_group(GROUP)

	health = HealthComponent.new()
	health.name = "HealthComponent"
	# Coarse whole-body trauma budget (about 7.5 kJ). Ordinary deaths come from VitalsComponent.
	health.max_health = 300.0
	add_child(health)
	vitals = VitalsComponent.new()
	vitals.name = "VitalsComponent"
	add_child(vitals)
	rig = HumanoidRig.new()
	rig.name = "Rig"
	add_child(rig)
	rig.build(health, vitals)
	ragdoll = ActiveRagdoll.new()
	ragdoll.name = "ActiveRagdoll"
	add_child(ragdoll)
	ragdoll.setup(rig)
	animator = ProceduralAnimator.new()
	animator.name = "ProceduralAnimator"
	add_child(animator)
	animator.setup(rig)
	gore = GoreComponent.new()
	gore.name = "GoreComponent"
	add_child(gore)
	gore.setup(rig, vitals)
	brain = NPCBrain.new()
	brain.name = "NPCBrain"
	brain.wanders = wanders
	add_child(brain)
	brain.setup(self)

	for hitbox: HitboxComponent in rig.hitboxes.values():
		hitbox.hit.connect(_on_hit)
		hitbox.fractured.connect(_on_structure_changed.unbind(2))
		hitbox.joint_destroyed.connect(_on_structure_changed.unbind(1))
	gore.part_severed.connect(_on_part_severed)
	health.died.connect(func(_info: DamageInfo) -> void: vitals.kill("massive trauma"))

	rig.start_simulation()
	if armed:
		_give_weapon()


func hips_position() -> Vector3:
	return rig.bones[Anatomy.HIPS].global_position


func is_alive() -> bool:
	return vitals.is_alive()


func is_armed() -> bool:
	return weapon_model != null


func leg_functional(side: int) -> bool:
	if is_paralyzed():
		return false
	for base: String in ["UpperLeg", "LowerLeg"]:
		var hitbox := rig.hitboxes[Anatomy.limb(base, side)]
		if hitbox.is_fractured or hitbox.joint_ruined or hitbox.detached:
			return false
	return true


func arm_functional(side: int) -> bool:
	for base: String in ["UpperArm", "LowerArm"]:
		var hitbox := rig.hitboxes[Anatomy.limb(base, side)]
		if hitbox.is_fractured or hitbox.joint_ruined or hitbox.detached:
			return false
	return true


## A broken vertebral column anywhere in the trunk paralyses the legs.
func is_paralyzed() -> bool:
	for part: StringName in [Anatomy.HIPS, Anatomy.SPINE, Anatomy.CHEST]:
		if rig.hitboxes[part].spinal_injury:
			return true
	return false


## Share of body weight the legs can still carry: both legs 1.0, one leg 0.4, none 0.
func leg_support() -> float:
	var working := int(leg_functional(Anatomy.LEFT)) + int(leg_functional(Anatomy.RIGHT))
	var value: float = [0.0, 0.4, 1.0][working]
	if rig.hitboxes[Anatomy.HIPS].is_fractured:
		value *= 0.4
	return value


func drop_weapon() -> void:
	if weapon_model == null:
		return
	var pickup := WeaponPickup.create(&"ak47")
	var xform := weapon_model.global_transform
	var hand := rig.bones[Anatomy.limb("LowerArm", _weapon_side)]
	weapon_model.queue_free()
	weapon_model = null
	get_parent().add_child(pickup)
	pickup.global_transform = xform
	pickup.linear_velocity = hand.linear_velocity


## Group callback: weapons announce gunfire to every NPC.
func hear_noise(position: Vector3) -> void:
	brain.hear_noise(position)


## Text for the HUD inspector.
func inspect_text() -> String:
	var injuries: PackedStringArray = []
	for part in rig.order:
		var hitbox := rig.hitboxes[part]
		if hitbox.is_severed:
			injuries.append(String(part) + " severed")
		elif hitbox.is_fractured:
			injuries.append(String(part) + " fractured")
		elif hitbox.joint_ruined:
			injuries.append(String(part) + " joint destroyed")
	if is_paralyzed():
		injuries.append("spinal cord injury")
	var state: String = NPCBrain.State.keys()[brain.state]
	var text := "%s [%s]\n%s" % ["Armed NPC" if armed else "Civilian", state.capitalize(), vitals.summary()]
	if not injuries.is_empty():
		text += "\n" + ", ".join(injuries)
	return text


func _give_weapon() -> void:
	weapon_model = WeaponModels.ak47(false)
	rig.bones[Anatomy.limb("LowerArm", _weapon_side)].add_child(weapon_model)
	# The forearm hangs along -Y at rest; turn the rifle so its barrel follows the forearm.
	weapon_model.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0.0, -0.17, -0.03))


func _on_hit(hitbox: HitboxComponent, info: DamageInfo) -> void:
	brain.on_hit(hitbox, info)
	if hitbox.region == HitboxComponent.Region.ARM and hitbox.side == _weapon_side and info.energy > 60.0:
		drop_weapon()


func _on_part_severed(part: StringName) -> void:
	if part == Anatomy.HEAD:
		vitals.kill("decapitation")
	ragdoll.rebuild_inertia()
	_on_structure_changed()


## Fractures, ruined joints and amputations decide which limbs the motors may still drive.
func _on_structure_changed() -> void:
	for side: int in [Anatomy.LEFT, Anatomy.RIGHT]:
		var leg := 1.0 if leg_functional(side) else 0.0
		for base: String in ["UpperLeg", "LowerLeg", "Foot"]:
			ragdoll.set_part_strength(Anatomy.limb(base, side), leg)
		var arm := 1.0 if arm_functional(side) else 0.0
		for base: String in ["UpperArm", "LowerArm"]:
			ragdoll.set_part_strength(Anatomy.limb(base, side), arm)
	if not arm_functional(_weapon_side):
		drop_weapon()
