class_name SimSelectionMarker
extends Node2D

## The two ranges the AI actually reasons about, drawn around the selected
## entity: its sensor radius (what it can see) and its action radius (what it
## can reach). A dot marks the centre so a selection stays findable when the
## camera is pulled far out.
##
## Drawn here rather than on every entity because a circle per creature is
## unreadable with a whole population on screen, and it belongs to the
## selection, not the debug overlay, so it shows with labels switched off.
## It also lives beside the entities rather than on them, so a freed entity
## takes nothing with it — the marker just stops tracking.

const SENSOR_COLOR := Color(0.13, 0.52, 0.75, 0.75)
const REACH_COLOR := Color(0.95, 0.45, 0.05, 0.95)
const CENTRE_COLOR := Color(0.95, 0.45, 0.05, 0.95)

## Line widths in SCREEN pixels — divided by the camera zoom before drawing, so
## the circles stay just as readable pulled out over the whole map as they are
## up close. Without that they thin to nothing at low zoom and look missing.
const SENSOR_WIDTH := 2.5
const REACH_WIDTH := 3.0
const CENTRE_RADIUS := 4.0

var _target: SimEntity
var _sensor: SimSensorComponent
var _action: SimActionComponent

func _ready() -> void:
	z_index = 200
	visible = false

## Follows `entity`, or hides when passed null.
func track(entity: SimEntity) -> void:
	_target = entity
	_sensor = entity.get_component(&"sensor") as SimSensorComponent if entity != null else null
	_action = entity.get_component(&"action") as SimActionComponent if entity != null else null
	visible = entity != null
	set_process(entity != null)
	if entity != null:
		global_position = entity.global_position
	queue_redraw()

func _process(_delta: float) -> void:
	if not is_instance_valid(_target):
		track(null)
		return
	global_position = _target.global_position
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(_target):
		return
	var scale_up := 1.0 / maxf(_camera_zoom(), 0.01)
	if _sensor != null:
		draw_arc(Vector2.ZERO, _sensor.radius, 0.0, TAU, 72, SENSOR_COLOR, SENSOR_WIDTH * scale_up)
	if _action != null:
		draw_arc(Vector2.ZERO, _action.radius, 0.0, TAU, 48, REACH_COLOR, REACH_WIDTH * scale_up)
	draw_circle(Vector2.ZERO, CENTRE_RADIUS * scale_up, CENTRE_COLOR)

## Draw scale of the active camera. Falls back to 1.0 outside the tree.
func _camera_zoom() -> float:
	if not is_inside_tree():
		return 1.0
	return get_viewport_transform().get_scale().x
