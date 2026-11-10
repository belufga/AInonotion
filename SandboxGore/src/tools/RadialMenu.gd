class_name RadialMenu
extends Control
## Radial selection wheel. The mouse is captured during play, so the wheel keeps its own
## virtual cursor fed with relative motion; releasing the key picks the highlighted wedge.

const OUTER := 270.0
const INNER := 95.0
const DEADZONE := 30.0

var items: Array[Dictionary] = []  ## Each needs "label"; "color" is optional.
var title := ""
var is_open := false

var _cursor := Vector2.ZERO
var _hover := -1


func _ready() -> void:
	# Already in the tree here: the anchors-only preset would keep the control at zero size.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func open(p_title: String, p_items: Array[Dictionary], current := -1) -> void:
	title = p_title
	items = p_items
	_cursor = Vector2.ZERO
	_hover = current
	is_open = true
	visible = true
	queue_redraw()


func feed(relative: Vector2) -> void:
	_cursor = (_cursor + relative).limit_length(OUTER)
	if _cursor.length() > DEADZONE and not items.is_empty():
		# Wedge 0 is centred on twelve o'clock; indices run clockwise.
		var angle := fposmod(atan2(_cursor.x, -_cursor.y), TAU)
		_hover = int(round(angle / (TAU / items.size()))) % items.size()
	queue_redraw()


## Closes the wheel and returns the highlighted index, or -1 if nothing was chosen.
func close() -> int:
	is_open = false
	visible = false
	return _hover


func _draw() -> void:
	var count := items.size()
	if count == 0:
		return
	var center := size * 0.5
	var step := TAU / count
	var font := get_theme_default_font()
	draw_circle(center, OUTER + 16.0, Color(0.0, 0.0, 0.0, 0.35))
	for i in count:
		var hovered := i == _hover
		var color: Color = items[i].get("color", Color(0.4, 0.4, 0.45))
		var fill := Color(color.r, color.g, color.b, 0.92) if hovered else Color(color.r * 0.3, color.g * 0.3, color.b * 0.3, 0.85)
		var middle := i * step
		draw_colored_polygon(_wedge(center, INNER, OUTER + (14.0 if hovered else 0.0), middle - step * 0.5 + 0.012, middle + step * 0.5 - 0.012), fill)
		var label := String(items[i].label).replace(" ", "\n")
		var lines := label.count("\n") + 1
		var anchor := center + _direction(middle) * (INNER + OUTER) * 0.5 + Vector2(-60.0, 6.0 - (lines - 1) * 9.0)
		draw_multiline_string_outline(font, anchor, label, HORIZONTAL_ALIGNMENT_CENTER, 120.0, 16, -1, 4, Color(0.0, 0.0, 0.0, 0.9))
		draw_multiline_string(font, anchor, label, HORIZONTAL_ALIGNMENT_CENTER, 120.0, 16, -1, Color.WHITE if hovered else Color(0.86, 0.86, 0.86))
	draw_circle(center, INNER - 6.0, Color(0.05, 0.05, 0.06, 0.9))
	draw_string(font, center + Vector2(-INNER, 7.0), title, HORIZONTAL_ALIGNMENT_CENTER, INNER * 2.0, 20, Color.WHITE)
	draw_circle(center + _cursor, 5.0, Color.WHITE)


func _direction(angle: float) -> Vector2:
	return Vector2(sin(angle), -cos(angle))


func _wedge(center: Vector2, inner: float, outer: float, from: float, to: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var segments := 10
	for s in segments + 1:
		points.append(center + _direction(lerpf(from, to, s / float(segments))) * outer)
	for s in segments + 1:
		points.append(center + _direction(lerpf(to, from, s / float(segments))) * inner)
	return points
