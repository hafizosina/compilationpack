class_name EcsSelectionMarker
extends Node2D

## Draws a ring and centre dot on each selected entity, and the drag box while
## one is being drawn. EcsSelectionSystem sets the marks each frame; main.gd the box.

const REACH_COLOR := Color(0.95, 0.45, 0.05, 0.95)
const CENTRE_COLOR := Color(0.95, 0.45, 0.05, 0.95)
const BOX_FILL := Color(0.95, 0.45, 0.05, 0.12)
const BOX_EDGE := Color(0.95, 0.45, 0.05, 0.9)

## Sizes in screen pixels; divided by zoom before drawing.
const REACH_WIDTH := 3.0
const CENTRE_RADIUS := 4.0
const BOX_WIDTH := 2.0

var _points := PackedVector2Array()
var _reaches := PackedFloat32Array()
var _box := Rect2()
var _has_box: bool = false

func _ready() -> void:
	z_index = 200

## Marks each of `points`, in world coordinates. A reach of zero draws only the dot.
func show_marks(points: PackedVector2Array, reaches: PackedFloat32Array) -> void:
	if points == _points and reaches == _reaches:
		return
	_points = points
	_reaches = reaches
	queue_redraw()

## Shows the drag box, in world coordinates.
func show_box(box: Rect2) -> void:
	_box = box
	_has_box = true
	queue_redraw()

func clear_box() -> void:
	_has_box = false
	queue_redraw()

func clear() -> void:
	_points = PackedVector2Array()
	_reaches = PackedFloat32Array()
	_has_box = false
	queue_redraw()

func _draw() -> void:
	var scale_up := 1.0 / maxf(_camera_zoom(), 0.01)
	for i in _points.size():
		var at := to_local(_points[i])
		if _reaches[i] > 0.0:
			draw_arc(at, _reaches[i], 0.0, TAU, 64, REACH_COLOR, REACH_WIDTH * scale_up)
		draw_circle(at, CENTRE_RADIUS * scale_up, CENTRE_COLOR)
	if _has_box:
		var local := Rect2(to_local(_box.position), _box.size)
		draw_rect(local, BOX_FILL)
		draw_rect(local, BOX_EDGE, false, BOX_WIDTH * scale_up)

## Draw scale of the active camera. Falls back to 1.0 outside the tree.
func _camera_zoom() -> float:
	if not is_inside_tree():
		return 1.0
	return get_viewport_transform().get_scale().x
