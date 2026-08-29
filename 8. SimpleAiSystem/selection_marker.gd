class_name SimSelectionMarker
extends Node2D

## Ring around the entity currently being inspected, plus its sensor and action
## radii — the two distances the AI actually reasons about.
##
## Drawn here rather than on every entity because a circle per creature is
## unreadable with a whole population on screen, and it belongs to the
## selection, not the debug overlay, so it shows with labels switched off.
##
## It lives beside the entities rather than on them so a freed entity takes
## nothing with it — the marker just stops tracking.

const RING_COLOR := Color(0.85, 0.5, 0.08, 0.95)
const RING_RADIUS := 42.0
const RING_WIDTH := 3.0

const SENSOR_COLOR := Color(0.15, 0.55, 0.75, 0.5)
const REACH_COLOR := Color(0.9, 0.35, 0.15, 0.7)

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
	draw_arc(Vector2.ZERO, RING_RADIUS, 0.0, TAU, 48, RING_COLOR, RING_WIDTH)
	if _sensor != null:
		draw_arc(Vector2.ZERO, _sensor.radius, 0.0, TAU, 64, SENSOR_COLOR, 2.0)
	if _action != null:
		draw_arc(Vector2.ZERO, _action.radius, 0.0, TAU, 48, REACH_COLOR, 2.0)
