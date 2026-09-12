class_name EcsMovementSystem
extends EcsSystem

## Walks everything holding a destination toward it. It has no idea why anything
## wants to be anywhere — wander, flee and go-eat-that all arrive here as the
## same two fields.

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
			move.has_destination = false
			move.velocity = Vector2.ZERO
			continue
		move.velocity = to_go.normalized() * move.speed
		here.position += move.velocity * delta
