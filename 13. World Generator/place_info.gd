class_name WorldPlaceInfo
extends Control

## What the pinned L3 cell is, on a daluang slip like the key: its terrain as the heading with its swatch,
## then position, height, climate, humidity, water and cell. An X in the corner closes it (touch-sized).

signal closed

const WIDE := 280.0
const PAD := 14.0
const ROW := 24.0
const STRIP := 12.0
const TITLE := 30.0
const CLOSE := 40.0
## Metres from the sea level to the highest land, and to the deepest sea, for height read as 0..1.
const TOP_M := 8000.0
const DEEP_M := 6000.0

var _title: String = ""
var _swatch: Color
var _rows: Array = []

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

## Shows `cell` of `map`.
func show_cell(map: WorldMap, cell: Vector2i) -> void:
	var i := WorldMap.index(cell)
	var kind := map.kind(cell)
	_title = kind[0]
	_swatch = kind[1]
	var lat := 90.0 - (cell.y + 0.5) / WorldMap.SIZE.y * 180.0
	var lon := (cell.x + 0.5) / WorldMap.SIZE.x * 360.0 - 180.0
	var h := map.height[i]
	_rows = [["Position", "%.1f° %s, %.1f° %s" % [absf(lat), "N" if lat >= 0.0 else "S", absf(lon), "E" if lon >= 0.0 else "W"]]]
	if h >= WorldMap.SEA:
		_rows.append(["Elevation", "%s m" % _thousands((h - WorldMap.SEA) / (1.0 - WorldMap.SEA) * TOP_M)])
	else:
		_rows.append(["Depth", "%s m" % _thousands((WorldMap.SEA - h) / WorldMap.SEA * DEEP_M)])
	_rows.append(["Climate", WorldMap.band(0, map.heat[i])])
	_rows.append(["Humidity", WorldMap.band(2, map.humidity[i])])
	if map.river[i] == 1:
		_rows.append(["Water", "River (flow %d)" % roundi(map.flow[i])])
	elif map.lake[i] == 1:
		_rows.append(["Water", "Lake"])
	_rows.append(["Cell", "%d, %d" % [cell.x, cell.y]])
	custom_minimum_size = Vector2(WIDE, PAD * 2.0 + STRIP + TITLE + _rows.size() * ROW)
	size = custom_minimum_size
	queue_redraw()

static func _thousands(value: float) -> String:
	var digits := str(roundi(value / 10.0) * 10)
	var out := ""
	for k in digits.length():
		if k > 0 and (digits.length() - k) % 3 == 0:
			out += ","
		out += digits[k]
	return out

func _close_rect() -> Rect2:
	return Rect2(Vector2(size.x - CLOSE - 6.0, STRIP + 4.0), Vector2(CLOSE, CLOSE))

func _gui_input(event: InputEvent) -> void:
	# Touch only: the project turns a click into a touch too, so the click itself would count twice.
	if event is InputEventScreenTouch and event.pressed:
		accept_event()
		if _close_rect().has_point(event.position):
			closed.emit()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(Rect2(rect.position + Vector2(4, 5), rect.size), Color(0, 0, 0, 0.3))
	draw_rect(rect, WorldMapKey.PAPER)
	draw_rect(rect.grow(-3.0), WorldMapKey.SEPIA, false, 2.0)
	draw_rect(rect.grow(-7.0), WorldMapKey.SEPIA, false, 1.0)
	var x0 := 9.0
	var k := 0
	while x0 + STRIP <= size.x - 9.0:
		draw_colored_polygon(PackedVector2Array([Vector2(x0, 9.0), Vector2(x0 + STRIP, 9.0), Vector2(x0 + STRIP * 0.5, 9.0 + STRIP)]),
			WorldMapKey.INDIGO if k % 2 == 0 else WorldMapKey.OCHRE)
		x0 += STRIP
		k += 1
	var font := get_theme_font(&"font", &"Label")
	var font_size := get_theme_font_size(&"font_size", &"Label")
	var y0 := 9.0 + STRIP + TITLE - 6.0
	var swatch := Vector2(PAD + 8.0, y0 - font_size * 0.35)
	draw_circle(swatch, 8.0, _swatch.darkened(0.2))
	draw_circle(swatch - Vector2(1.2, 1.2), 6.4, _swatch)
	draw_arc(swatch, 8.0, 0.0, TAU, 20, WorldMapKey.SEPIA, 1.3, true)
	draw_string(font, Vector2(PAD + 22.0, y0), _title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size + 3, WorldMapKey.SEPIA)
	var x := _close_rect()
	var c := x.get_center()
	draw_line(c + Vector2(-7, -7), c + Vector2(7, 7), WorldMapKey.SEPIA, 2.4, true)
	draw_line(c + Vector2(7, -7), c + Vector2(-7, 7), WorldMapKey.SEPIA, 2.4, true)
	draw_line(Vector2(PAD, y0 + 8.0), Vector2(size.x - PAD, y0 + 8.0), WorldMapKey.PAPER_DARK, 1.0)
	for i in _rows.size():
		var y := y0 + 8.0 + (i + 1) * ROW - 4.0
		draw_string(font, Vector2(PAD, y), _rows[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, WorldMapKey.OCHRE)
		draw_string(font, Vector2(PAD + 92.0, y), _rows[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, WorldMapKey.SEPIA)
