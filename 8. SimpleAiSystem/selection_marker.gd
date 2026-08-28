class_name SimSelectionMarker
extends Node2D

## Ring around the entity currently being inspected, plus that entity's wander
## leash: the circle it picks destinations inside, a tether to its spawn point
## and a cross marking it.
##
## The leash is drawn here rather than on every entity because one circle per
## creature is unreadable with a whole population on screen — and it belongs to
## the selection, not to the debug overlay, so it shows with labels switched off.
##
## It lives beside the entities rather than on them so a freed entity takes
## nothing with it — the marker just stops tracking.

const RING_COLOR := Color(0.85, 0.5, 0.08, 0.95)
const RING_RADIUS := 42.0
const RING_WIDTH := 3.0

const LEASH_COLOR := Color(0.15, 0.55, 0.75, 0.55)
const HOME_COLOR := Color(0.1, 0.4, 0.6, 0.9)
## Half-length of each arm of the cross marking the spawn point.
const HOME_MARK := 7.0

var _target: SimEntity
var _wander: SimWanderComponent

func _ready() -> void:
	z_index = 200
	visible = false

## Follows `entity`, or hides when passed null.
func track(entity: SimEntity) -> void:
	_target = entity
	_wander = entity.get_component(&"wander") as SimWanderComponent if entity != null else null
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
	if _wander == null:
		return
	# Centred on the SPAWN POINT, not the entity: wander picks its destinations
	# within `radius` of home, so the circle stays put while the entity roams
	# inside it. The tether shows how far it has strayed.
	var home := to_local(_target.home_position)
	draw_arc(home, _wander.radius, 0.0, TAU, 64, LEASH_COLOR, 2.0)
	draw_line(Vector2.ZERO, home, LEASH_COLOR, 1.0)
	draw_line(home - Vector2(HOME_MARK, 0.0), home + Vector2(HOME_MARK, 0.0), HOME_COLOR, 2.0)
	draw_line(home - Vector2(0.0, HOME_MARK), home + Vector2(0.0, HOME_MARK), HOME_COLOR, 2.0)
