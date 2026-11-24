class_name WorldHoldMark
extends Control

## Feedback for zooming past a level's limit, drawn in the map key's style: a daluang disc in the screen's
## middle with a sepia rim, the level it leads to in its centre, and a ring of segments that fill, tumpal
## colours in turn, one a held wheel notch (or smoothly with a pinch); each fill pops.

const RADIUS: float = 34.0
const RING: float = 9.0

## Segments in the ring.
var steps: int = 5:
	set(value):
		steps = value
		queue_redraw()
## How much of the ring is filled, 0..1.
var filled: float = 0.0:
	set(value):
		filled = clampf(value, 0.0, 1.0)
		queue_redraw()
## The level it leads to, shown in the middle.
var label: String = "":
	set(value):
		label = value
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2.ONE * (RADIUS + RING + 6.0) * 2.0
	size = custom_minimum_size
	pivot_offset = size * 0.5
	modulate.a = 0.0

## Shows the ring `amount` full, popping when a new segment fills.
func show_fill(amount: float) -> void:
	var before := floori(filled * steps + 0.001)
	filled = amount
	modulate.a = 1.0
	if floori(filled * steps + 0.001) > before:
		scale = Vector2.ONE * 1.18
		create_tween().tween_property(self, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Fades out and empties.
func fade() -> void:
	if modulate.a <= 0.0:
		return
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func() -> void: filled = 0.0)

func _draw() -> void:
	var middle := size * 0.5
	var outer := RADIUS + RING
	draw_circle(middle + Vector2(3, 4), outer + 3.0, Color(0, 0, 0, 0.3))
	draw_circle(middle, outer + 3.0, WorldMapKey.PAPER)
	draw_arc(middle, outer + 3.0, 0.0, TAU, 48, WorldMapKey.SEPIA, 2.0, true)
	var gap := 0.12
	var span := TAU / steps
	var lit := filled * steps
	for k in steps:
		var from := -PI * 0.5 + k * span + gap * 0.5
		var to := from + span - gap
		draw_arc(middle, RADIUS + RING * 0.5, from, to, 12, WorldMapKey.PAPER_DARK, RING, true)
		var part := clampf(lit - k, 0.0, 1.0)
		if part > 0.0:
			draw_arc(middle, RADIUS + RING * 0.5, from, from + (to - from) * part, 12,
				WorldMapKey.OCHRE if k % 2 == 0 else WorldMapKey.INDIGO, RING, true)
	draw_arc(middle, RADIUS, 0.0, TAU, 40, WorldMapKey.SEPIA, 1.2, true)
	var font := get_theme_font(&"font", &"Label")
	var font_size := get_theme_font_size(&"font_size", &"Label") + 6
	var wide := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, middle + Vector2(-wide.x * 0.5, font_size * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_size, WorldMapKey.SEPIA)
