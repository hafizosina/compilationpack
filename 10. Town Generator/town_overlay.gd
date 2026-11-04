class_name EcsTownOverlay
extends Node2D

## Draws building footprints, rooms and the build tool's drag preview, in world space. A
## dumb view: EcsTownOverlaySystem hands it footprints and rooms, main.gd the preview. An
## open building is a dashed outline, a closed one solid with a light fill; each room is
## tinted its own colour, a sealed area red.

const FOOTPRINT := Color("#B98A32")
const CLOSED_FILL := Color(0.725, 0.541, 0.196, 0.12)
const SEALED := Color(0.62, 0.17, 0.15, 0.35)
const PREVIEW := Color(1.0, 1.0, 1.0, 0.85)
const REFUSED := Color("#9E2B25")
const LABEL := Color("#2A2016")
const LABEL_SIZE: int = 14
const GHOST := Color(1.0, 1.0, 1.0, 0.7)
const GHOST_REFUSED := Color(1.0, 0.45, 0.4, 0.7)

## Building footprints, in cells, and whether each is closed.
var footprints: Array[Rect2i] = []
var closed: Array[bool] = []
## Rooms and sealed areas: {id, cells, sealed, label}.
var rooms: Array = []
var show_rooms: bool = true
## The hovered tool's ghost: what it would place, where (world pixels), the cells it acts on,
## and why it would be refused ("" when it wouldn't).
var ghost_texture: Texture2D
var ghost_rect: Rect2 = Rect2()
var ghost_cells: Rect2i = Rect2i()
var ghost_reason: String = ""
## Cells of a dragged line that would be refused.
var bad_cells: Array[Vector2i] = []
## Cells the tool would act on, and whether the drag would be refused.
var preview: Array[Vector2i] = []
var preview_rect: Rect2i = Rect2i()
var preview_bad: bool = false

func _draw() -> void:
	var cell := float(EcsTownGrid.CELL)
	if show_rooms:
		for room: Dictionary in rooms:
			var tint := SEALED if room["sealed"] else Color.from_hsv(fmod(float(room["id"]) * 0.618, 1.0), 0.6, 0.9, 0.3)
			for at: Vector2i in room["cells"]:
				draw_rect(Rect2(Vector2(at) * cell, Vector2(cell, cell)), tint, true)
	if show_rooms:
		var font := ThemeDB.fallback_font
		for room: Dictionary in rooms:
			var text: String = room.get("label", "")
			if text == "":
				continue
			var middle := Vector2.ZERO
			for at: Vector2i in room["cells"]:
				middle += Vector2(at)
			middle = (middle / (room["cells"] as Array).size() + Vector2(0.5, 0.5)) * cell
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
			draw_string(font, middle - Vector2(width * 0.5, -LABEL_SIZE * 0.35), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, LABEL)
	for k in footprints.size():
		var area := Rect2(Vector2(footprints[k].position) * cell, Vector2(footprints[k].size) * cell)
		if k < closed.size() and closed[k]:
			draw_rect(area, CLOSED_FILL, true)
			draw_rect(area, FOOTPRINT, false, 4.0)
		else:
			_dashed_rect(area, FOOTPRINT, 2.0)
	_draw_ghost(cell)
	var colour := REFUSED if preview_bad else PREVIEW
	if preview_rect.has_area():
		draw_rect(Rect2(Vector2(preview_rect.position) * cell, Vector2(preview_rect.size) * cell), colour, false, 2.0)
	for at in preview:
		var mark := REFUSED if bad_cells.has(at) else colour
		draw_rect(Rect2(Vector2(at) * cell + Vector2(4, 4), Vector2(cell - 8, cell - 8)), mark, false, 2.0)

func _draw_ghost(cell: float) -> void:
	if not ghost_cells.has_area():
		return
	var refused := ghost_reason != ""
	if ghost_texture != null:
		draw_texture_rect(ghost_texture, ghost_rect, false, GHOST_REFUSED if refused else GHOST)
	var area := Rect2(Vector2(ghost_cells.position) * cell, Vector2(ghost_cells.size) * cell)
	draw_rect(area, REFUSED if refused else PREVIEW, false, 2.0)
	if refused:
		var font := ThemeDB.fallback_font
		var at := area.position + Vector2(area.size.x + 6.0, LABEL_SIZE)
		draw_string_outline(font, at, ghost_reason, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, 4, Color.WHITE)
		draw_string(font, at, ghost_reason, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, REFUSED)

func _dashed_rect(area: Rect2, colour: Color, width: float) -> void:
	var corners := [area.position, Vector2(area.end.x, area.position.y), area.end, Vector2(area.position.x, area.end.y)]
	for k in 4:
		draw_dashed_line(corners[k], corners[(k + 1) % 4], colour, width, 8.0)
