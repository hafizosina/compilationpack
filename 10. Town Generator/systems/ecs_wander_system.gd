class_name EcsWanderSystem
extends EcsSystem

## A wanderer standing still waits out its pause, then gets a random destination within its
## radius, kept inside `bounds`. Moving is EcsMovementSystem's.

var _bounds: Rect2

func _init(bounds: Rect2) -> void:
	_bounds = bounds

func label() -> StringName:
	return &"wander"

func run(world: EcsWorld, delta: float) -> void:
	var view := world.view([EcsPositionComponent, EcsMovementComponent, EcsWanderComponent])
	var places := view.column(EcsPositionComponent)
	var moves := view.column(EcsMovementComponent)
	var wanders := view.column(EcsWanderComponent)
	for k in view.ids.size():
		var move := moves[k] as EcsMovementComponent
		if move.has_destination:
			continue
		var wander := wanders[k] as EcsWanderComponent
		wander.pause_left -= delta
		if wander.pause_left > 0.0:
			continue
		var from := (places[k] as EcsPositionComponent).position
		var to := from + Vector2.RIGHT.rotated(randf() * TAU) * wander.radius * sqrt(randf())
		move.destination = to.clamp(_bounds.position, _bounds.end)
		move.has_destination = true
		move.time_left = 0.0
		wander.pause_left = randf_range(wander.pause_min, wander.pause_max)
