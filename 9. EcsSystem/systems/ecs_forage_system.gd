class_name EcsForageSystem
extends EcsSystem

## Go and get a berry, if there is room to put one.
##
## This is the second rung of the decision ladder and it is worth seeing how
## little that costs. It has the same shape as EcsLowBrainSystem — look at an
## entity with nothing to do, write a destination — and it runs **before** it in
## the scheduler. That is the entire priority mechanism: forage gets first
## refusal, and anything it declines falls through to aimless wandering. No
## state machine, no priority field, no brain arbitrating between the two.
##
## An entity whose inventory is full is simply skipped, so it goes back to
## wandering on its own.
##
## It writes the same `destination` field the low brain writes, so everything
## downstream — movement, collision, render — is unaware that foraging exists.

func label() -> StringName:
	return &"forage"

func run(world: EcsWorld, _delta: float) -> void:
	# Loose berries only: a carried one has no EcsPositionComponent, so it drops
	# out of this query with nothing asked to hide it.
	var loose := world.query([EcsPositionComponent, EcsPickableComponent])
	if loose.is_empty():
		return

	for id in world.query([EcsPositionComponent, EcsMovementComponent, EcsInventoryComponent]):
		var move := world.get_component(id, EcsMovementComponent) as EcsMovementComponent
		if move.has_destination:
			continue
		var bag := world.get_component(id, EcsInventoryComponent) as EcsInventoryComponent
		if bag.items.size() >= bag.capacity:
			continue

		var here := (world.get_component(id, EcsPositionComponent) as EcsPositionComponent).position
		# Nearest wins. O(foragers x berries) — 10 x 24 here. A search radius or
		# a spatial index goes in this loop and nowhere else.
		var best := EcsWorld.NO_ENTITY
		var best_distance := INF
		for berry in loose:
			var there := (world.get_component(berry, EcsPositionComponent) as EcsPositionComponent).position
			var distance := here.distance_squared_to(there)
			if distance < best_distance:
				best_distance = distance
				best = berry
		if best == EcsWorld.NO_ENTITY:
			continue

		move.destination = (world.get_component(best, EcsPositionComponent) as EcsPositionComponent).position
		move.has_destination = true
