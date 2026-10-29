class_name EcsSelectionMarker
extends Node2D

## Draws a ring and centre dot on the selected entity. EcsSelectionSystem sets it
## each frame.

const REACH_COLOR := Color(0.95, 0.45, 0.05, 0.95)
const CENTRE_COLOR := Color(0.95, 0.45, 0.05, 0.95)

## Sizes in screen pixels; divided by zoom before drawing.
const REACH_WIDTH := 3.0
const CENTRE_RADIUS := 4.0

var _reach: float = 0.0

func _ready() -> void:
	z_index = 200
	visible = false

## Shows the marker at `world_position`. A `reach` of zero draws only the dot.
func show_at(world_position: Vector2, reach: float) -> void:
	global_position = world_position
	_reach = reach
	visible = true
	queue_redraw()

func clear() -> void:
	visible = false

func _draw() -> void:
	var scale_up := 1.0 / maxf(_camera_zoom(), 0.01)
	if _reach > 0.0:
		draw_arc(Vector2.ZERO, _reach, 0.0, TAU, 64, REACH_COLOR, REACH_WIDTH * scale_up)
	draw_circle(Vector2.ZERO, CENTRE_RADIUS * scale_up, CENTRE_COLOR)

## Draw scale of the active camera. Falls back to 1.0 outside the tree.
func _camera_zoom() -> float:
	if not is_inside_tree():
		return 1.0
	return get_viewport_transform().get_scale().x
