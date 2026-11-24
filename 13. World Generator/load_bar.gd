class_name WorldLoadBar
extends Control

## The loading bar shown on the cover while a world is made: a daluang slip with a title and a sepia-framed
## bar filling in indigo with a tumpal edge. `value` is eased toward, so steps in progress fill smoothly.

const SLIP := Vector2(380, 96)
const STRIP := 10.0

## Progress, 0 to 1.
var value: float = 0.0
var title: String = "Drawing the world"
var _shown: float = 0.0

func _init() -> void:
	custom_minimum_size = SLIP
	size = SLIP
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Empties the bar at once.
func restart() -> void:
	value = 0.0
	_shown = 0.0
	queue_redraw()

func _process(delta: float) -> void:
	if not is_visible_in_tree() or is_equal_approx(_shown, value):
		return
	_shown = move_toward(_shown, value, delta * 1.5)
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(Rect2(rect.position + Vector2(4, 5), rect.size), Color(0, 0, 0, 0.3))
	draw_rect(rect, WorldMapKey.PAPER)
	draw_rect(rect.grow(-3.0), WorldMapKey.SEPIA, false, 2.0)
	draw_rect(rect.grow(-7.0), WorldMapKey.SEPIA, false, 1.0)
	var font := get_theme_font(&"font", &"Label")
	var font_size := get_theme_font_size(&"font_size", &"Label") + 2
	var wide := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2((size.x - wide) * 0.5, 36.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, WorldMapKey.SEPIA)
	var bar := Rect2(Vector2(20, 52), Vector2(size.x - 40, 24))
	draw_rect(bar, WorldMapKey.PAPER_DARK)
	var fill := Rect2(bar.position, Vector2(bar.size.x * clampf(_shown, 0.0, 1.0), bar.size.y))
	draw_rect(fill, WorldMapKey.INDIGO)
	var x0 := bar.position.x
	var k := 0
	while x0 + STRIP <= fill.end.x:
		draw_colored_polygon(PackedVector2Array([Vector2(x0, bar.end.y), Vector2(x0 + STRIP, bar.end.y),
			Vector2(x0 + STRIP * 0.5, bar.end.y - STRIP * 0.8)]), WorldMapKey.OCHRE if k % 2 == 0 else WorldMapKey.PAPER)
		x0 += STRIP
		k += 1
	draw_rect(bar, WorldMapKey.SEPIA, false, 1.6)
