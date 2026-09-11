class_name EcsSelectionMarker
extends Node2D

## The reach the selected entity actually reasons about, drawn around it, with a
## dot marking the centre so a selection stays findable when the camera is
## pulled far out.
##
## Unlike module 8's marker this one does not follow anything: it holds no
## reference to an entity and runs no _process. EcsSelectionSystem pushes it a
## position and a radius each frame, because in this module a node is a view of
## the world and never a reader of it.

const REACH_COLOR := Color(0.95, 0.45, 0.05, 0.95)
const CENTRE_COLOR := Color(0.95, 0.45, 0.05, 0.95)

## Line widths in SCREEN pixels — divided by the camera zoom before drawing, so
## the ring stays just as readable pulled out over the whole arena as it is up
## close. Without that it thins to nothing at low zoom and looks missing.
const REACH_WIDTH := 3.0
const CENTRE_RADIUS := 4.0

var _reach: float = 0.0

func _ready() -> void:
	z_index = 200
	visible = false

## Shows the marker at `world_position`. A `reach` of zero draws the centre dot
## alone, which is what a rabbit or a dagger gets — nothing about it can strike.
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
