class_name EcsTownOverlay
extends Node2D

## Draws building footprints and the build tool's drag preview, in world space. A dumb
## view: EcsTownOverlaySystem hands it footprints, main.gd the preview. An open building
## is a dashed outline; a closed one solid, with a light fill.

const FOOTPRINT := Color("#B98A32")
const CLOSED_FILL := Color(0.725, 0.541, 0.196, 0.12)
const PREVIEW := Color(1.0, 1.0, 1.0, 0.85)
const REFUSED := Color("#9E2B25")

## Building footprints, in cells, and whether each is closed.
var footprints: Array[Rect2i] = []
var closed: Array[bool] = []
## Cells the tool would act on, and whether the drag would be refused.
var preview: Array[Vector2i] = []
var preview_rect: Rect2i = Rect2i()
var preview_bad: bool = false

func _draw() -> void:
	var cell := float(EcsTownGrid.CELL)
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
