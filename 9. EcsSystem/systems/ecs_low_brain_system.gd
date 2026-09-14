class_name EcsLowBrainSystem
extends EcsSystem

## Decides where to go, then stops caring. It writes a destination into the
## movement component and never touches a position — the split that lets a
## smarter brain take its place later without the movement system noticing.
##
## This is the first stage of the pipeline: decide, then act, then draw.

func label() -> StringName:
	return &"low_brain"

func run(world: EcsWorld, delta: float) -> void:
	for id in world.query([EcsPositionComponent, EcsMovementComponent, EcsLowBrainComponent]):
		var move := world.get_component(id, EcsMovementComponent) as EcsMovementComponent
		if move.has_destination:
			continue
		var brain := world.get_component(id, EcsLowBrainComponent) as EcsLowBrainComponent
		brain.pause_left -= delta
		if brain.pause_left > 0.0:
			continue
		brain.pause_left = randf_range(brain.pause_min, brain.pause_max)
		var here := world.get_component(id, EcsPositionComponent) as EcsPositionComponent
		move.destination = EcsConst.random_point_near(here.position, brain.radius, 0.25)
		move.has_destination = true
