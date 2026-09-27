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
## **Eating off the ground is a kill; eating from the bag is not.** A berry in a
## bag is already a record — it died when it was picked up — so eating it is
## only taking the record out. One on the ground is an entity, so this adds
## EcsDyingFlag and EcsEntityManager frees it and its nodes at the top of the
## next tick. The flag is a claim from the instant it lands: EcsPickupSystem
## runs after this and refuses a berry carrying it, so one berry cannot be both
## eaten here and pocketed there in the same tick.
##
## One berry per decision: the flag names one meal, and once it is eaten the
## flag names something Dying, so nothing more happens until the brain runs
## again (20 Hz) and names the next. A creature with five berries and a deep
## hunger eats them over five decisions rather than inhaling the lot at once.

func label() -> StringName:
	return &"consume"

func run(world: EcsWorld, _delta: float) -> void:
	for id in world.query([EcsEatIntentFlag, EcsHungerComponent]):
		var intent := world.get_component(id, EcsEatIntentFlag) as EcsEatIntentFlag
		var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent

		if intent.record_uid != "":
			# Out of the bag. The record is the whole of the item — it died when
			# it was picked up — so eating it is only taking it out; its
			# nutrition is the snapshot's, whatever that instance was given.
			var record := _take_from_bag(world, id, intent.record_uid)
			if record == null:
				continue
			var carried := record.component(EcsConsumableComponent) as EcsConsumableComponent
			hunger.fullness = minf(hunger.fullness + carried.nutrition, hunger.max_fullness)
			continue

		var meal := intent.target_id
		if not _still_food(world, meal) or not _within_reach(world, id, meal):
			# Eaten or claimed since the brain named it, or moved out of reach
			# on a list a tick stale. Nothing happens; the brain decides again.
			continue
		var food := world.get_component(meal, EcsConsumableComponent) as EcsConsumableComponent
		hunger.fullness = minf(hunger.fullness + food.nutrition, hunger.max_fullness)
		world.add(meal, EcsDyingFlag.new())

## Alive, edible, and not already claimed — eaten by someone earlier this tick.
func _still_food(world: EcsWorld, meal: int) -> bool:
	return world.is_alive(meal) and world.has(meal, EcsConsumableComponent) \
		and not world.has(meal, EcsDyingFlag)

## Takes the record with `uid` out of this entity's bag and returns it, or
## null if it is not there or is not food.
func _take_from_bag(world: EcsWorld, id: int, uid: String) -> EcsItemRecord:
	var bag := world.get_component(id, EcsInventoryComponent) as EcsInventoryComponent
	if bag == null:
		return null
	for slot in bag.items.size():
		var record := bag.items[slot]
		if record.uid == uid and record.component(EcsConsumableComponent) != null:
			bag.items.remove_at(slot)
			return record
	return null

## Is `meal` lying on the ground within this entity's action area? Nothing is
## removed from anywhere: it is on the ground, and in a moment it will not exist.
func _within_reach(world: EcsWorld, id: int, meal: int) -> bool:
	var action := world.get_component(id, EcsActionComponent) as EcsActionComponent
	return action != null and action.reached.has(meal) \
		and world.has(meal, EcsPositionComponent)
