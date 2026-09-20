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
## **It only chases what the entity can see.** The candidates are the ids in its
## own EcsSensorComponent.perceived — what its sensor area overlapped last tick
## — so a berry across the map does not exist as far as this system is
## concerned. Carrying a sensor is the whole of "this entity can find food": an
## entity without one never forages and needs no flag saying so.
##
## That also retired the O(foragers x berries) scan this used to do. The
## broadphase culls to a handful of neighbours in C++ and the ranking below
## sorts those few, so the loop no longer grows with the size of the world.
##
## An entity whose inventory is full is simply skipped, so it goes back to
## wandering on its own.
##
## It writes the same `destination` field the low brain writes, so everything
## downstream — movement, collision, node_sync — is unaware that foraging exists.

func label() -> StringName:
	return &"forage"

func run(world: EcsWorld, _delta: float) -> void:
	for id in world.query([EcsPositionComponent, EcsMovementComponent,
			EcsInventoryComponent, EcsSensorComponent]):
		var move := world.get_component(id, EcsMovementComponent) as EcsMovementComponent
		if move.has_destination:
			continue
		var bag := world.get_component(id, EcsInventoryComponent) as EcsInventoryComponent
		if bag.items.size() >= bag.capacity:
			continue

		var sensor := world.get_component(id, EcsSensorComponent) as EcsSensorComponent
		if sensor.perceived.is_empty():
			continue

		var here := (world.get_component(id, EcsPositionComponent) as EcsPositionComponent).position
		# Nearest of what it can see wins. The list is already culled to
		# neighbours by the broadphase, so this ranks three or four things.
		var best := EcsWorld.NO_ENTITY
		var best_distance := INF
		for seen in sensor.perceived:
			# A berry someone else took this tick has lost its position and is
			# no longer anywhere to walk to.
			if not world.has(seen, EcsPickableComponent) or not world.has(seen, EcsPositionComponent):
				continue
			var there := (world.get_component(seen, EcsPositionComponent) as EcsPositionComponent).position
			var distance := here.distance_squared_to(there)
			if distance < best_distance:
				best_distance = distance
				best = seen
		if best == EcsWorld.NO_ENTITY:
			continue

		move.destination = (world.get_component(best, EcsPositionComponent) as EcsPositionComponent).position
		move.has_destination = true
