class_name EcsMovementSystem
extends EcsSystem

## Moves entities toward their destination. Each trip gets a time budget
## (distance / speed * `timeout_slack` + `timeout_grace`); when it runs out the
## destination is dropped as if reached, so stuck entities decide again. Speed is
## scaled by EcsDashingFlag while it is present.

func label() -> StringName:
	return &"movement"

func run(world: EcsWorld, delta: float) -> void:
	var view := world.view([EcsPositionComponent, EcsMovementComponent])
	var moves := view.column(EcsMovementComponent)
	var places := view.column(EcsPositionComponent)
	for k in view.ids.size():
		var id := view.ids[k]
		var move := moves[k] as EcsMovementComponent
		if not move.has_destination:
			move.velocity = Vector2.ZERO
			continue
		var here := places[k] as EcsPositionComponent
		var to_go := move.destination - here.position
		var speed := move.speed
		var dashing := world.get_component(id, EcsDashingFlag) as EcsDashingFlag
		if dashing != null:
			speed *= dashing.speed_scale
		var step := speed * delta
		if to_go.length() <= maxf(step, move.arrive_radius):
			here.position = move.destination
			_release(move)
			continue

		if move.time_left <= 0.0:
			# New trip: set its time budget.
			move.time_left = to_go.length() / maxf(speed, 0.01) \
				* move.timeout_slack + move.timeout_grace
		move.time_left -= delta
		if move.time_left <= 0.0:
			# Out of time; give up.
			_release(move)
			continue

		move.velocity = to_go.normalized() * speed
		here.position += move.velocity * delta

## Ends a trip and resets its clock.
func _release(move: EcsMovementComponent) -> void:
	move.has_destination = false
	move.velocity = Vector2.ZERO
	move.time_left = 0.0
