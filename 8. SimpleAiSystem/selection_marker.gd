class_name SimSelectionMarker
extends Node2D

## Ring drawn around the entity currently being inspected.
##
## It lives beside the entities rather than on them so selection still reads
## with the debug overlay switched off, and so a freed entity takes nothing
## with it — the marker just stops tracking.

const RING_COLOR := Color(0.85, 0.5, 0.08, 0.95)
const RING_RADIUS := 42.0
const RING_WIDTH := 3.0

var _target: SimEntity

func _ready() -> void:
	z_index = 200
	visible = false

## Follows `entity`, or hides when passed null.
func track(entity: SimEntity) -> void:
	_target = entity
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
