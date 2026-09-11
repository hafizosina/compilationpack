class_name EcsWanderSystem
extends EcsSystem

## Picks somewhere to go, then stops caring. It writes a destination into the
## movement component and never touches a position — the split that lets a brain
## replace it later without the movement system noticing.

func label() -> StringName:
	return &"wander"

func run(world: EcsWorld, delta: float) -> void:
	for id in world.query([EcsPositionComponent, EcsMovementComponent, EcsWanderComponent],
			[EcsDeadComponent]):
		var move := world.get_component(id, EcsMovementComponent) as EcsMovementComponent
		if move.has_destination:
			continue
		var wander := world.get_component(id, EcsWanderComponent) as EcsWanderComponent
		wander.pause_left -= delta
		if wander.pause_left > 0.0:
			continue
		wander.pause_left = randf_range(wander.pause_min, wander.pause_max)
		var here := world.get_component(id, EcsPositionComponent) as EcsPositionComponent
		move.destination = EcsConst.wander_point(here.position, wander.radius)
		move.has_destination = true
