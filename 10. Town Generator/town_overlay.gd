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

## Building footprints, in cells, and whether each is closed.
var footprints: Array[Rect2i] = []
var closed: Array[bool] = []
## Rooms and sealed areas: {id, cells, sealed}.
var rooms: Array = []
var show_rooms: bool = true
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
	for k in footprints.size():
		var area := Rect2(Vector2(footprints[k].position) * cell, Vector2(footprints[k].size) * cell)
		if k < closed.size() and closed[k]:
			draw_rect(area, CLOSED_FILL, true)
			draw_rect(area, FOOTPRINT, false, 4.0)
		else:
			_dashed_rect(area, FOOTPRINT, 2.0)
	var colour := REFUSED if preview_bad else PREVIEW
	if preview_rect.has_area():
		draw_rect(Rect2(Vector2(preview_rect.position) * cell, Vector2(preview_rect.size) * cell), colour, false, 2.0)
	for at in preview:
		draw_rect(Rect2(Vector2(at) * cell + Vector2(4, 4), Vector2(cell - 8, cell - 8)), colour, false, 2.0)

func _dashed_rect(area: Rect2, colour: Color, width: float) -> void:
	var corners := [area.position, Vector2(area.end.x, area.position.y), area.end, Vector2(area.position.x, area.end.y)]
	for k in 4:
		draw_dashed_line(corners[k], corners[(k + 1) % 4], colour, width, 8.0)
