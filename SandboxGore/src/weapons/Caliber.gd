class_name Caliber
extends Resource
## Projectile definition. Every energy figure in the ballistics model derives from mass,
## velocity and diameter, so a new round only needs real-world numbers.

const AIR_DENSITY := 1.225
const REFERENCE_AREA := 6.36e-5  ## 9 mm cross-section; skin perforation cost is quoted for this area.

@export var display_name := "9x19mm Parabellum"
@export var mass := 0.008               ## kg
@export var muzzle_velocity := 360.0    ## m/s
@export var diameter := 0.009           ## m
@export var air_drag := 0.38            ## Drag coefficient in air.
@export var hardness := 1.0             ## >1 for soft projectiles that deform against hard targets.
@export var flesh_drag_stable := 1.0    ## Tissue drag multiplier while travelling point-first.
@export var flesh_drag_tumbling := 1.0  ## Tissue drag multiplier after the bullet yaws.
@export var yaw_depth := 100.0          ## Metres of tissue before a rifle bullet starts to tumble.
@export var impulse_scale := 5.0        ## Gameplay exaggeration of momentum transfer.
@export var tracer_color := Color(1.0, 0.85, 0.5)

var area: float:
	get:
		return PI * diameter * diameter * 0.25

static var _cache: Dictionary[StringName, Caliber] = {}


func muzzle_energy() -> float:
	return 0.5 * mass * muzzle_velocity * muzzle_velocity


## Quadratic air drag constant k in dv/dt = -k * |v| * v.
func air_drag_k() -> float:
	return 0.5 * AIR_DENSITY * air_drag * area / mass


static func parabellum_9mm() -> Caliber:
	return _preset(&"9mm", "9x19mm Parabellum", 0.008, 360.0, 0.009, 0.38, 1.6, 1.0, 1.0, 100.0, 5.0)


## Steel-core 7.62 mm: stable at first, then yaws and dumps energy, which widens exit wounds.
static func soviet_762x39() -> Caliber:
	return _preset(&"7.62", "7.62x39mm", 0.0079, 715.0, 0.0079, 0.33, 1.0, 0.4, 2.6, 0.09, 5.0)


static func buckshot_00() -> Caliber:
	return _preset(&"00buck", "12ga 00 buckshot", 0.0035, 380.0, 0.0084, 0.5, 2.0, 1.25, 1.25, 100.0, 7.0)


static func fragment_m67() -> Caliber:
	return _preset(&"frag", "M67 fragment", 0.0005, 1300.0, 0.006, 1.1, 1.3, 1.4, 1.4, 100.0, 3.0)


static func _preset(key: StringName, p_name: String, p_mass: float, p_velocity: float, p_diameter: float,
		p_air: float, p_hardness: float, p_stable: float, p_tumbling: float, p_yaw: float, p_impulse: float) -> Caliber:
	if _cache.has(key):
		return _cache[key]
	var c := Caliber.new()
	c.display_name = p_name
	c.mass = p_mass
	c.muzzle_velocity = p_velocity
	c.diameter = p_diameter
	c.air_drag = p_air
	c.hardness = p_hardness
	c.flesh_drag_stable = p_stable
	c.flesh_drag_tumbling = p_tumbling
	c.yaw_depth = p_yaw
	c.impulse_scale = p_impulse
	_cache[key] = c
	return c
