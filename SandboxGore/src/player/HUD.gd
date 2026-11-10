class_name HUD
extends CanvasLayer
## Heads-up display: spread-driven crosshair, weapon and ammunition readout, contextual hints,
## the target inspector that exposes an NPC's vitals, performance counters and the radial wheel.

const HELP_TEXT := """WASD move    Shift sprint    Space jump    V noclip
1 Toolgun   2 Pistol   3 Shotgun   4 AK-47   5 Grenade   (wheel cycles)
LMB fire / use    RMB aim / secondary    R reload    F pick up weapon
Q tool wheel    Tab spawn wheel    E + mouse rotate held object
T slow motion    F5 restart    F6 clear gore    F1 help    Esc free the mouse"""

var radial: RadialMenu

var _crosshair: Crosshair
var _weapon: Label
var _hint: Label
var _inspect: Label
var _stats: Label
var _help: Label


class Crosshair extends Control:
	var gap := 8.0

	func _draw() -> void:
		var center := size * 0.5
		for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			draw_line(center + direction * gap, center + direction * (gap + 9.0), Color(0.0, 0.0, 0.0, 0.7), 3.5)
			draw_line(center + direction * gap, center + direction * (gap + 9.0), Color(1.0, 1.0, 1.0, 0.9), 1.5)
		draw_circle(center, 1.6, Color(1.0, 1.0, 1.0, 0.9))


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_crosshair = Crosshair.new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_crosshair)

	_weapon = _label(root, 26, Control.PRESET_BOTTOM_RIGHT, HORIZONTAL_ALIGNMENT_RIGHT)
	_weapon.offset_left = -640.0
	_weapon.offset_top = -78.0
	_weapon.offset_right = -24.0
	_weapon.offset_bottom = -42.0
	_hint = _label(root, 16, Control.PRESET_BOTTOM_RIGHT, HORIZONTAL_ALIGNMENT_RIGHT)
	_hint.offset_left = -900.0
	_hint.offset_top = -40.0
	_hint.offset_right = -24.0
	_hint.offset_bottom = -14.0
	_inspect = _label(root, 17, Control.PRESET_TOP_LEFT, HORIZONTAL_ALIGNMENT_LEFT)
	_inspect.offset_left = 24.0
	_inspect.offset_top = 20.0
	_inspect.offset_right = 620.0
	_inspect.offset_bottom = 260.0
	_stats = _label(root, 15, Control.PRESET_TOP_RIGHT, HORIZONTAL_ALIGNMENT_RIGHT)
	_stats.offset_left = -520.0
	_stats.offset_top = 16.0
	_stats.offset_right = -24.0
	_stats.offset_bottom = 110.0
	_help = _label(root, 15, Control.PRESET_BOTTOM_LEFT, HORIZONTAL_ALIGNMENT_LEFT)
	_help.offset_left = 24.0
	_help.offset_top = -150.0
	_help.offset_right = 760.0
	_help.offset_bottom = -14.0
	_help.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_help.text = HELP_TEXT

	radial = RadialMenu.new()
	root.add_child(radial)


func set_weapon(title: String, ammo: String, hint: String) -> void:
	_weapon.text = title if ammo == "" else "%s   %s" % [title, ammo]
	_hint.text = hint


func set_inspect(text: String) -> void:
	_inspect.text = text


func set_stats(text: String) -> void:
	_stats.text = text


func set_crosshair_gap(pixels: float) -> void:
	if absf(_crosshair.gap - pixels) > 0.25:
		_crosshair.gap = pixels
		_crosshair.queue_redraw()


func toggle_help() -> void:
	_help.visible = not _help.visible


func _label(parent: Control, font_size: int, preset: Control.LayoutPreset, alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.set_anchors_preset(preset)
	label.horizontal_alignment = alignment
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override(&"outline_size", 5)
	parent.add_child(label)
	return label
