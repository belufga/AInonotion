class_name BallisticMaterial
extends RefCounted
## Penetration model for one surface type.
##
## Energy lost per metre is dE/dx = -(drag * A/m * E + strength * A): inertial drag, which
## dominates in soft media, plus yield strength, which dominates in wood, metal and bone.

const META_SURFACE := &"surface"  ## StringName id on a collider.
const META_WALL := &"wall"        ## Wall thickness in metres for hollow props (crates, barrels).

var id: StringName
var drag_density := 0.0   ## kg/m^3: density times drag coefficient.
var strength := 0.0       ## Pa.
var debris_color := Color.GRAY
var leaves_hole := true
var sparks := false

static var _table: Dictionary[StringName, BallisticMaterial] = {}


static func lookup(p_id: StringName) -> BallisticMaterial:
	if _table.is_empty():
		_add(&"concrete", 2300.0, 2.5e9, Color(0.62, 0.6, 0.57))
		_add(&"wood", 600.0, 6.0e7, Color(0.55, 0.38, 0.2))
		_add(&"metal", 7800.0, 4.0e9, Color(1.0, 0.8, 0.4), true, true)
		_add(&"glass", 2500.0, 5.0e7, Color(0.85, 0.95, 1.0), false)
		_add(&"rubber", 1100.0, 2.0e7, Color(0.08, 0.08, 0.08))
		_add(&"flesh", 740.0, 1.0e6, Color(0.4, 0.0, 0.0), false)
		_add(&"bone", 1500.0, 1.5e8, Color(0.9, 0.88, 0.8), false)
	return _table.get(p_id, _table[&"concrete"])


static func of(collider: Object) -> BallisticMaterial:
	if collider != null and collider.has_meta(META_SURFACE):
		return lookup(collider.get_meta(META_SURFACE))
	return lookup(&"concrete")


## Energy remaining after `thickness` metres. Negative means the projectile stopped inside.
func energy_after(cal: Caliber, e0: float, thickness: float, drag_multiplier := 1.0) -> float:
	if thickness <= 0.0:
		return e0
	var a := drag_density * drag_multiplier * cal.area / cal.mass
	var s := strength * cal.area * cal.hardness
	if a < 1e-5:
		return e0 - s * thickness
	return (e0 + s / a) * exp(-a * thickness) - s / a


## Depth at which a projectile with energy `e0` comes to rest.
func stop_depth(cal: Caliber, e0: float, drag_multiplier := 1.0) -> float:
	var a := drag_density * drag_multiplier * cal.area / cal.mass
	var s := strength * cal.area * cal.hardness
	if s <= 0.0:
		return INF
	if a < 1e-5:
		return e0 / s
	return log(1.0 + a * e0 / s) / a


static func _add(p_id: StringName, p_drag: float, p_strength: float, p_color: Color, p_hole := true, p_sparks := false) -> void:
	var m := BallisticMaterial.new()
	m.id = p_id
	m.drag_density = p_drag
	m.strength = p_strength
	m.debris_color = p_color
	m.leaves_hole = p_hole
	m.sparks = p_sparks
	_table[p_id] = m
