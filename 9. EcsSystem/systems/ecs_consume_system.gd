class_name EcsConsumeSystem
extends EcsSystem

## Carries out the decision to eat. It does not make it.
##
## `EcsLowBrainSystem` raises EcsEatIntentFlag, naming the meal, when it is
## hungry enough and has food at hand; this turns that into the berry ending and
## points going back onto the bar. The split is the same one the whole module
## runs on — one place decides, another acts — and it is what keeps the brain
## from growing hands. This is step 6's intent pattern: the flag is the intent,
## this is its executor, and it never reads the brain. Anything that raises the
## flag gets a creature fed.
##
## ## Two ways to have food at hand, and no inventory required
##
## A carrier eats out of its `EcsInventoryComponent`. A **grazer** — a rabbit,
## which has no inventory at all — eats what its action area is touching, off
## the ground, where it stands. Which of the two the named meal is, this works
## out; which meal to eat was the brain's choice (bag first), not this file's.
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
## comes back if it is put down. An eaten one is gone, so this adds
## EcsDyingFlag and EcsEntityManager frees it and its nodes at the top of the
## next tick. The flag is a claim from the instant it lands: EcsPickupSystem
## runs after this and refuses a berry carrying it, so one berry cannot be both
## eaten here and pocketed there in the same tick.
## That contrast is the clearest example in the module of node lifetime tracking
## the entity while what a node *does* tracks the components.
##
## One berry per decision: the flag names one meal, and once it is eaten the
## flag names something Dying, so nothing more happens until the brain runs
## again (20 Hz) and names the next. A creature with five berries and a deep
## hunger eats them over five decisions rather than inhaling the lot at once.

func label() -> StringName:
	return &"consume"

func run(world: EcsWorld, _delta: float) -> void:
	for id in world.query([EcsEatIntentFlag, EcsHungerComponent]):
		var meal := (world.get_component(id, EcsEatIntentFlag) as EcsEatIntentFlag).target_id
		if not _still_food(world, meal):
			# Eaten or claimed since the brain named it. Nothing happens; the
			# brain decides again with a fresher picture.
			continue
		if not _take_from_bag(world, id, meal) and not _within_reach(world, id, meal):
			# Neither held nor touching: it moved out of reach since the brain
			# decided, on a list a tick stale.
			continue

		var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent
		var food := world.get_component(meal, EcsConsumableComponent) as EcsConsumableComponent
		hunger.fullness = minf(hunger.fullness + food.nutrition, hunger.max_fullness)
		world.add(meal, EcsDyingFlag.new())

## Alive, edible, and not already claimed — eaten by someone earlier this tick.
func _still_food(world: EcsWorld, meal: int) -> bool:
	return world.is_alive(meal) and world.has(meal, EcsConsumableComponent) \
		and not world.has(meal, EcsDyingFlag)

## If `meal` is in this entity's bag, takes it out and says so. A held entity has
## no position, so "is it anywhere" does not apply — being in a pocket is where
## it is.
func _take_from_bag(world: EcsWorld, id: int, meal: int) -> bool:
	var bag := world.get_component(id, EcsInventoryComponent) as EcsInventoryComponent
	if bag == null or not bag.items.has(meal):
		return false
	bag.items.erase(meal)
	return true

## Is `meal` lying on the ground within this entity's action area? Nothing is
## removed from anywhere: it is on the ground, and in a moment it will not exist.
func _within_reach(world: EcsWorld, id: int, meal: int) -> bool:
	var action := world.get_component(id, EcsActionComponent) as EcsActionComponent
	return action != null and action.reached.has(meal) \
		and world.has(meal, EcsPositionComponent)
