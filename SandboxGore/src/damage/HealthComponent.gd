class_name HealthComponent
extends Node
## Structural health for any damageable entity: props, barrels, glass and, as a coarse trauma
## score, humanoids. Physiological death of a humanoid is decided by VitalsComponent.

signal damaged(info: DamageInfo, applied: float)
signal died(info: DamageInfo)

const META_KEY := &"health_component"

@export var max_health := 100.0
@export var joules_per_hp := 20.0  ## Ballistic, shrapnel or blunt energy that removes one hit point.
@export var kpa_per_hp := 1.0      ## Blast overpressure that removes one hit point.
@export var invulnerable := false

var health := 100.0
var dead := false


func _enter_tree() -> void:
	health = max_health
	get_parent().set_meta(META_KEY, self)


## Returns the component registered on `target`, or null.
static func of(target: Object) -> HealthComponent:
	if target != null and target.has_meta(META_KEY):
		return target.get_meta(META_KEY)
	return null


func fraction() -> float:
	return health / max_health if max_health > 0.0 else 0.0


func apply_damage(info: DamageInfo) -> float:
	if dead or invulnerable:
		return 0.0
	var amount := info.amount
	if amount <= 0.0:
		if info.type == DamageInfo.Type.BLAST:
			amount = info.overpressure / kpa_per_hp
		else:
			amount = info.energy / joules_per_hp
	amount = minf(amount, health)
	health -= amount
	damaged.emit(info, amount)
	if health <= 0.0:
		kill(info)
	return amount


func kill(info: DamageInfo = null) -> void:
	if dead:
		return
	dead = true
	health = 0.0
	died.emit(info)
