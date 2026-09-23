class_name EcsMovementSystem
extends EcsSystem

## Walks everything holding a destination toward it. It has no idea why anything
## wants to be anywhere — wander, flee and go-eat-that all arrive here as the
## same two fields.
##
## ## Every trip is on a clock, priced from what it should cost
##
## Nothing downstream of an intent can tell the difference between "still
## walking" and "wedged". Soft collision corrects a position *after* movement
## proposes it, so an entity pushed off its line keeps proposing the same step
## forever: the destination stays live, `has_destination` stays true, and the
## rungs above — forage, low_brain — skip it precisely because it already has
## somewhere to be. That is the stuck entity, and it is a livelock, not a bug in
## any one stage.
##
## So a destination is not a standing order, it is a budget. The cost of a walk
## is its length over its speed, and the budget is that cost times
## `timeout_slack` plus `timeout_grace` — priced once, on the tick this system
## first sees the intent, so a trip across the map gets proportionally longer to
## make than a trip next door. When it runs out the destination is dropped
## exactly as if it had been reached, and the entity falls back down the ladder
## to decide again with everything it knows now.
##
## Giving up is therefore the same event as arriving, as far as every other
## system is concerned. Nothing else learns a new field.

func label() -> StringName:
	return &"movement"

func run(world: EcsWorld, delta: float) -> void:
	for id in world.query([EcsPositionComponent, EcsMovementComponent]):
		var move := world.get_component(id, EcsMovementComponent) as EcsMovementComponent
		if not move.has_destination:
			move.velocity = Vector2.ZERO
			continue
		var here := world.get_component(id, EcsPositionComponent) as EcsPositionComponent
		var to_go := move.destination - here.position
		var step := move.speed * delta
		if to_go.length() <= maxf(step, move.arrive_radius):
			here.position = move.destination
			_release(move)
			continue

		if move.time_left <= 0.0:
			# A fresh intent: price the trip before walking any of it.
			move.time_left = to_go.length() / maxf(move.speed, 0.01) \
				* move.timeout_slack + move.timeout_grace
		move.time_left -= delta
		if move.time_left <= 0.0:
			# Bought time spent and still not there — something is in the way,
			# and it is not this system's business what. Let it go.
			_release(move)
			continue

		move.velocity = to_go.normalized() * move.speed
		here.position += move.velocity * delta

## Ends a trip, however it ended. The clock goes back to zero so the next
## destination written onto this component is priced as the new trip it is.
func _release(move: EcsMovementComponent) -> void:
	move.has_destination = false
	move.velocity = Vector2.ZERO
	move.time_left = 0.0
