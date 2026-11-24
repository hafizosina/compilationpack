class_name WorldMapKey
extends Control

## L3's key, drawn as a daluang slip: a sepia double frame, a tumpal strip along the top, the map mode's
## name, and each colour as a rounded swatch with a sepia rim beside its name. Drawn, not themed, like the
## debug overlay, since it is part of the map's art.

const PAPER := Color(0.88, 0.79, 0.61)
const PAPER_DARK := Color(0.80, 0.70, 0.52)
const SEPIA := Color(0.29, 0.19, 0.11)
const INDIGO := Color(0.20, 0.25, 0.40)
const OCHRE := Color(0.62, 0.30, 0.18)
const PAD := 14.0
const ROW := 22.0
const STRIP := 12.0
const TITLE := 26.0

## The heading.
var title: String = "":
	set(value):
		title = value
		_fit()
## Each entry: [name, colour].
var entries: Array = []:
	set(value):
		entries = value
		_fit()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _fit() -> void:
	var font := get_theme_font(&"font", &"Label")
	var size_px := get_theme_font_size(&"font_size", &"Label")
	var wide := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px + 2).x
	for entry: Array in entries:
		wide = maxf(wide, font.get_string_size(entry[0], HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x + ROW + 6.0)
	custom_minimum_size = Vector2(wide + PAD * 2.0, PAD * 2.0 + STRIP + TITLE + entries.size() * ROW)
	size = custom_minimum_size
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	draw_rect(Rect2(rect.position + Vector2(4, 5), rect.size), Color(0, 0, 0, 0.3))
	draw_rect(rect, PAPER)
	for k in int(size.y / 3.0):
		var y := k * 3.0 + rng.randf() * 2.0
		var x := rng.randf() * size.x
		draw_line(Vector2(x, y), Vector2(minf(x + rng.randf_range(20, 70), size.x), y), PAPER_DARK, 1.0)
	draw_rect(rect.grow(-3.0), SEPIA, false, 2.0)
	draw_rect(rect.grow(-7.0), SEPIA, false, 1.0)
	var top := 9.0
	var step := STRIP
	var x0 := 9.0
	var k := 0
	while x0 + step <= size.x - 9.0:
		draw_colored_polygon(PackedVector2Array([Vector2(x0, top), Vector2(x0 + step, top), Vector2(x0 + step * 0.5, top + STRIP)]),
			INDIGO if k % 2 == 0 else OCHRE)
		x0 += step
		k += 1
	draw_line(Vector2(9, top + STRIP), Vector2(size.x - 9, top + STRIP), SEPIA, 1.0)
	var font := get_theme_font(&"font", &"Label")
	var size_px := get_theme_font_size(&"font_size", &"Label")
	var y0 := top + STRIP + TITLE - 4.0
	draw_string(font, Vector2(PAD, y0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px + 2, SEPIA)
	for i in entries.size():
		var entry: Array = entries[i]
		var middle := Vector2(PAD + 7.0, y0 + 10.0 + i * ROW + ROW * 0.5)
		var colour: Color = entry[1]
		draw_circle(middle, 7.0, colour.darkened(0.2))
		draw_circle(middle - Vector2(1.2, 1.2), 5.6, colour)
		draw_arc(middle, 7.0, 0.0, TAU, 20, SEPIA, 1.3, true)
		draw_string(font, middle + Vector2(13.0, size_px * 0.35), entry[0], HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, SEPIA)
