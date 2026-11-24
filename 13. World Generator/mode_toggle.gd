class_name WorldModeToggle
extends Control

## L3's map mode picker, drawn like the map key: a column of daluang slips, each with a small ink icon (leaf,
## sun, mountain, drop) and its name; the chosen one pulled out toward the map, brighter, with a tumpal strip. Slips are big
## enough to tap, and a touch or a click picks.

signal picked(index: int)

const SLIP := Vector2(96, 80)
const GAP := 8.0
const LIFT := 8.0
const STRIP := 10.0

## Names, top to bottom.
var names: Array[String] = []:
	set(value):
		names = value
		custom_minimum_size = Vector2(SLIP.x + LIFT, names.size() * (SLIP.y + GAP) - GAP)
		size = custom_minimum_size
		queue_redraw()
## The slip shown chosen.
var selected: int = 0:
	set(value):
		selected = value
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _gui_input(event: InputEvent) -> void:
	var at := Vector2(-1, -1)
	if event is InputEventScreenTouch and event.pressed:
		at = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		at = event.position
	if at.x < 0.0:
		return
	var index := int(at.y / (SLIP.y + GAP))
	if index >= 0 and index < names.size():
		accept_event()
		selected = index
		picked.emit(index)

func _draw() -> void:
	var font := get_theme_font(&"font", &"Label")
	var font_size := get_theme_font_size(&"font_size", &"Label")
	for k in names.size():
		var chosen := k == selected
		var rect := Rect2(Vector2(LIFT if not chosen else 0.0, k * (SLIP.y + GAP)), SLIP)
		draw_rect(Rect2(rect.position + Vector2(3, 4), rect.size), Color(0, 0, 0, 0.3))
		draw_rect(rect, WorldMapKey.PAPER if chosen else WorldMapKey.PAPER_DARK)
		draw_rect(rect.grow(-3.0), WorldMapKey.SEPIA, false, 2.0 if chosen else 1.2)
		if chosen:
			var x0 := rect.position.x + 6.0
			var i := 0
			while x0 + STRIP <= rect.end.x - 6.0:
				draw_colored_polygon(PackedVector2Array([Vector2(x0, rect.position.y + 6.0), Vector2(x0 + STRIP, rect.position.y + 6.0),
					Vector2(x0 + STRIP * 0.5, rect.position.y + 6.0 + STRIP)]), WorldMapKey.INDIGO if i % 2 == 0 else WorldMapKey.OCHRE)
				x0 += STRIP
				i += 1
		_icon(k, rect.position + Vector2(SLIP.x * 0.5, SLIP.y * 0.45))
		var text := names[k]
		var wide := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, Vector2(rect.position.x + (SLIP.x - wide) * 0.5, rect.end.y - 10.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, WorldMapKey.SEPIA)

## Slip `k`'s icon, centred on `at`: leaf (biome), sun (heat), mountain (height), drop (humidity).
func _icon(k: int, at: Vector2) -> void:
	var ink := WorldMapKey.SEPIA
	match k:
		0:
			var leaf := PackedVector2Array()
			for i in 13:
				var t := float(i) / 12.0
				leaf.append(at + Vector2(sin(t * PI) * 11.0, -16.0 + t * 30.0).rotated(-0.5))
			for i in range(11, 0, -1):
				var t := float(i) / 12.0
				leaf.append(at + Vector2(-sin(t * PI) * 11.0, -16.0 + t * 30.0).rotated(-0.5))
			draw_colored_polygon(leaf, Color8(92, 136, 70))
			leaf.append(leaf[0])
			draw_polyline(leaf, ink, 1.6, true)
			draw_line(at + Vector2(0, -12).rotated(-0.5), at + Vector2(0, 16).rotated(-0.5), ink, 1.4, true)
		1:
			for i in 8:
				var a := i * TAU / 8.0
				draw_line(at + Vector2.from_angle(a) * 11.0, at + Vector2.from_angle(a) * 17.0, ink, 2.0, true)
			draw_circle(at, 9.0, Color8(214, 148, 84))
			draw_arc(at, 9.0, 0.0, TAU, 24, ink, 1.6, true)
		2:
			var hill := PackedVector2Array([at + Vector2(-18, 13), at + Vector2(-4, -15), at + Vector2(3, -3), at + Vector2(8, -9), at + Vector2(18, 13)])
			draw_colored_polygon(hill, Color8(128, 112, 96))
			draw_colored_polygon(PackedVector2Array([at + Vector2(-9, -5), at + Vector2(-4, -15), at + Vector2(1, -6)]), Color8(238, 236, 230))
			hill.append(hill[0])
			draw_polyline(hill, ink, 1.6, true)
		3:
			var drop := PackedVector2Array()
			for i in 17:
				var a := -PI / 6.0 + i * (PI * 4.0 / 3.0) / 16.0
				drop.append(at + Vector2(cos(a), sin(a)) * 10.0 + Vector2(0, 4))
			drop.append(at + Vector2(0, -16))
			draw_colored_polygon(drop, Color8(62, 110, 152))
			drop.append(drop[0])
			draw_polyline(drop, ink, 1.6, true)
