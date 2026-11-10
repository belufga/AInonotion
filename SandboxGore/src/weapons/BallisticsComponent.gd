class_name BallisticsComponent
extends Node
## Projectile emitter: what a weapon fires and how each shot enters the world.
##
## Holds the round, the pellets per shot and the hitscan range, and turns one trigger pull into
## BallisticShots handed to the hybrid ballistics service. It knows nothing about viewmodels,
## ammunition or input, so a turret or an armed NPC can compose one unchanged.

@export var caliber: Caliber
@export var pellets := 1
@export var hitscan_range := 60.0  ## Metres resolved instantly before the projectile phase.


## Fires one shot, every pellet of it, from `aim.origin` along the -Z axis of `aim` inside a cone
## of `spread_degrees`. `visual_origin` is where the tracers should appear to start.
func fire(aim: Transform3D, spread_degrees: float, attacker: Node = null, visual_origin := Vector3.INF) -> void:
	for i in pellets:
		var shot := BallisticShot.create(caliber, aim.origin, spread_direction(aim.basis, spread_degrees), attacker)
		Ballistics.fire(shot, hitscan_range, visual_origin)


## Random direction inside a cone around the aim axis.
static func spread_direction(aim: Basis, half_angle_degrees: float) -> Vector3:
	var radius := tan(deg_to_rad(half_angle_degrees)) * sqrt(randf())
	var angle := randf() * TAU
	return (aim * Vector3(cos(angle) * radius, sin(angle) * radius, -1.0)).normalized()


static func create(p_caliber: Caliber, p_hitscan_range: float, p_pellets := 1) -> BallisticsComponent:
	var component := BallisticsComponent.new()
	component.name = "BallisticsComponent"
	component.caliber = p_caliber
	component.hitscan_range = p_hitscan_range
	component.pellets = p_pellets
	return component
