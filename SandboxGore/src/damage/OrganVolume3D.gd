class_name OrganVolume3D
extends Area3D
## A vital organ or major artery: a collision volume inside a body part that only ballistic
## queries can hit. Trauma is translated into the matching physiological failure on VitalsComponent.

enum Kind { BRAIN, HEART, LUNG, LIVER, ARTERY }

signal traumatized(organ: OrganVolume3D, severity: float)

const LETHAL_BRAIN_ENERGY := 6.0  ## Joules of penetrating energy the brain cannot survive.

@export var kind := Kind.ARTERY
@export var organ_name := &"Organ"
@export var lung_index := 0       ## 0 left, 1 right.
@export var toughness := 60.0     ## Joules that destroy the organ outright.
@export var bleed_rate := 0.0     ## ml/s at normal pressure when fully ruptured.
@export var arterial := false
@export var path_length := 0.05   ## Typical distance a projectile travels inside the organ.

var integrity := 1.0
var vitals: VitalsComponent
var hitbox: HitboxComponent

var _wound: Wound


func _init() -> void:
	collision_layer = Layers.ORGANS
	collision_mask = 0
	monitoring = false
	monitorable = false
	input_ray_pickable = false


## `wound_position` and `wound_normal` describe the skin wound the organ bleeds out of.
func apply_trauma(energy: float, penetrating: bool, wound_position: Vector3, wound_normal: Vector3) -> void:
	if energy <= 0.0 or vitals == null or hitbox == null or hitbox.detached:
		return
	var severity := clampf(energy / toughness, 0.0, 1.0)
	integrity = maxf(integrity - severity, 0.0)
	match kind:
		Kind.BRAIN:
			if (penetrating and energy >= LETHAL_BRAIN_ENERGY) or integrity <= 0.4:
				vitals.damage_brain(1.0)
			else:
				vitals.damage_brain(severity * 0.4)
				vitals.knock_out(4.0 + severity * 20.0)
		Kind.HEART:
			# Any perforation ends effective pumping; the rest of the damage is the bleed.
			vitals.damage_heart(maxf(severity, 0.9) if penetrating else severity * 0.5)
			if penetrating:
				_bleed(1.0, wound_position, wound_normal)
		Kind.LUNG:
			vitals.damage_lung(lung_index, maxf(severity, 0.35) if penetrating else severity * 0.5)
			_bleed(clampf(0.5 + severity, 0.0, 1.0), wound_position, wound_normal)
		Kind.LIVER:
			vitals.add_pain(0.3)
			_bleed(clampf(0.4 + severity, 0.0, 1.0), wound_position, wound_normal)
		Kind.ARTERY:
			if penetrating or severity > 0.5:
				_bleed(clampf(0.6 + severity, 0.0, 1.0), wound_position, wound_normal)
	traumatized.emit(self, severity)


func _bleed(fraction: float, wound_position: Vector3, wound_normal: Vector3) -> void:
	var rate := bleed_rate * fraction
	if rate <= 0.0 or hitbox.bone == null:
		return
	if _wound != null and vitals.wounds.has(_wound):
		_wound.rate = minf(maxf(_wound.rate, rate) * 1.25, bleed_rate)
		return
	_wound = Wound.create(hitbox.bone, wound_position, wound_normal, rate, arterial, 0.0 if arterial else 90.0, organ_name)
	vitals.add_wound(_wound)
