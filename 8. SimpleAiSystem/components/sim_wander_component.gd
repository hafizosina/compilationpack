class_name SimWanderComponent
extends SimComponent

## Drunkard's walk: pick a random point near home, walk there, pause, repeat.
##
## Deliberately a *driver* sitting on top of SimMovementComponent rather than a
## mode inside it — Phase 2 turns Wander into a utility goal on the brain and
## deletes this component without touching movement. It reaches its sibling
## through the entity, never by node path.

## Radius around the entity's spawn point to pick destinations within. Doubles
## as a leash so nothing drifts off the painted map.
var radius: float = 256.0
## Seconds to idle after arriving, before picking the next destination.
var pause_min: float = 0.5
var pause_max: float = 2.0

var _rng := RandomNumberGenerator.new()
var _wait: float = 0.0
var _movement: SimMovementComponent

func slot() -> StringName:
	return &"wander"

func _ready() -> void:
	super()
	if entity == null:
		return
	_movement = entity.get_component(&"movement") as SimMovementComponent
	if _movement == null:
		push_warning("SimWanderComponent on '%s' has no movement component to drive" % entity.name)
		set_process(false)
		return
	_rng.randomize()
	# Stagger the first repath so a whole population never thinks on one frame.
	_wait = _rng.randf_range(0.0, pause_max)

func _process(delta: float) -> void:
	if _movement.is_moving():
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = _rng.randf_range(pause_min, pause_max)
	_movement.move_to(_pick_point(), SimMovementComponent.Gait.WALK)

func describe() -> Dictionary:
	return {
		"radius": "%.0f px" % radius,
		"pause": "%.1f - %.1f s" % [pause_min, pause_max],
		"next pick": "%.1f s" % maxf(_wait, 0.0),
	}

## A uniformly distributed point on the disc of `radius` around home, clamped to
## the world bounds. The sqrt keeps points from bunching at the centre.
func _pick_point() -> Vector2:
	var angle := _rng.randf_range(0.0, TAU)
	var distance := sqrt(_rng.randf()) * radius
	var point := entity.home_position + Vector2.RIGHT.rotated(angle) * distance
	var bounds := SimConst.WORLD_BOUNDS
	return Vector2(
		clampf(point.x, bounds.position.x, bounds.end.x),
		clampf(point.y, bounds.position.y, bounds.end.y)
	)
