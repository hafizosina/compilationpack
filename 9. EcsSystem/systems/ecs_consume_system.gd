class_name EcsConsumeSystem
extends EcsSystem

## Carries out the decision to eat. It does not make it.
##
## `EcsLowBrainSystem` puts a creature in the EAT state when it is hungry enough
## and has food at hand; this turns that into the berry ending and points going
## back onto the bar. The split is the same one the whole module runs on — one place
## decides, another acts — and it is what keeps the brain from growing hands. It
## is also step 6's intent pattern in miniature: `state` is the intent, and this
## is its executor.
##
## ## Two ways to have food at hand, and no inventory required
##
## A carrier eats out of its `EcsInventoryComponent`. A **grazer** — a rabbit,
## which has no inventory at all — eats what its action area is touching, off
## the ground, where it stands. The bag is checked first only because a thing
## already held is the nearer of the two; neither path is a special case of the
## other, and an entity carrying none of the components for one simply takes
## the other.
##
## That is why eating never grew a dependency on the bag. "I am hungry and there
## is food within reach" is the real condition, and a pocket is just one place
## reach can mean.
##
## Reach is whatever the physics server last reported, the same as
## EcsPickupSystem and for the same reason: the arithmetic that used to confirm
## it was the identical condition on numbers about a pixel fresher. What is
## still asked of a candidate is that it is alive and still somewhere.
##
## **Eating is a kill, and picking up is not.** A berry in a bag has merely lost
## its EcsPositionComponent: still alive, still holding its components, and it
## comes back if it is put down. An eaten one is gone, so this writes a kill
## note and EcsEntityManager frees it and its nodes at the top of the next tick.
## That contrast is the clearest example in the module of node lifetime tracking
## the entity while what a node *does* tracks the components.
##
## One bite per tick, deliberately: a creature with five berries and a deep
## hunger eats them over five ticks rather than inhaling the lot in one frame,
## and the brain gets to re-decide between each.

func label() -> StringName:
	return &"consume"

func run(world: EcsWorld, _delta: float) -> void:
	var lifecycle := world.get_singleton(EcsLifecycleComponent) as EcsLifecycleComponent
	if lifecycle == null:
		return
	for id in world.query([EcsLowBrainComponent, EcsHungerComponent]):
		var brain := world.get_component(id, EcsLowBrainComponent) as EcsLowBrainComponent
		if brain.state != EcsLowBrainComponent.State.EAT:
			continue

		var meal := _from_bag(world, id)
		if meal == EcsWorld.NO_ENTITY:
			meal = _within_reach(world, id)
		if meal == EcsWorld.NO_ENTITY:
			# The brain decided on a one-tick-stale list and the food has since
			# moved out of reach or been taken. Nothing happens; it decides
			# again next tick with a fresher one.
			continue

		var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent
		var food := world.get_component(meal, EcsConsumableComponent) as EcsConsumableComponent
		hunger.fullness = minf(hunger.fullness + food.nutrition, hunger.max_fullness)
		if not lifecycle.kill_requests.has(meal):
			lifecycle.kill_requests.append(meal)

## Something edible it is already carrying, taken out of the bag as it is eaten.
## A held entity has no position, so `_is_food`'s "is it anywhere" test does not
## apply to it — being in a pocket is where it is.
func _from_bag(world: EcsWorld, id: int) -> int:
	var bag := world.get_component(id, EcsInventoryComponent) as EcsInventoryComponent
	if bag == null:
		return EcsWorld.NO_ENTITY
	for slot in bag.items.size():
		var item: int = bag.items[slot]
		if world.is_alive(item) and world.has(item, EcsConsumableComponent):
			bag.items.remove_at(slot)
			return item
	return EcsWorld.NO_ENTITY

## Something edible lying within the action area, for a creature that has no
## pocket to have put it in. Nothing is removed from anywhere: it is on the
## ground, and in a moment it will not exist.
func _within_reach(world: EcsWorld, id: int) -> int:
	var action := world.get_component(id, EcsActionComponent) as EcsActionComponent
	if action == null:
		return EcsWorld.NO_ENTITY
	for touched in action.reached:
		if not world.is_alive(touched) or not world.has(touched, EcsConsumableComponent):
			continue
		# Still somewhere, rather than already eaten or pocketed this tick.
		if not world.has(touched, EcsPositionComponent):
			continue
		return touched
	return EcsWorld.NO_ENTITY
