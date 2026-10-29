class_name EcsConsumeSystem
extends EcsSystem

## Executes EcsEatIntentFlag: eats the named record from the bag, or the named
## entity in reach on the ground (flagging it dying). One meal per decision.

func label() -> StringName:
	return &"consume"

func run(world: EcsWorld, _delta: float) -> void:
	for id in world.query([EcsEatIntentFlag, EcsHungerComponent]):
		var intent := world.get_component(id, EcsEatIntentFlag) as EcsEatIntentFlag
		var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent

		if intent.record_uid != "":
			# From the bag.
			var record := _take_from_bag(world, id, intent.record_uid)
			if record == null:
				continue
			var carried := record.component(EcsConsumableComponent) as EcsConsumableComponent
			hunger.fullness = minf(hunger.fullness + carried.nutrition, hunger.max_fullness)
			continue

		var meal := intent.target_id
		if not _still_food(world, meal) or not _within_reach(world, id, meal):
			# Gone or out of reach; the brain will decide again.
			continue
		var food := world.get_component(meal, EcsConsumableComponent) as EcsConsumableComponent
		hunger.fullness = minf(hunger.fullness + food.nutrition, hunger.max_fullness)
		world.add(meal, EcsDyingFlag.new())

## Alive, edible and not already claimed this tick.
func _still_food(world: EcsWorld, meal: int) -> bool:
	return world.is_alive(meal) and world.has(meal, EcsConsumableComponent) \
		and not world.has(meal, EcsDyingFlag)

## Removes and returns the food record with `uid` from the bag, or null.
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

## Is `meal` on the ground within this entity's action area?
func _within_reach(world: EcsWorld, id: int, meal: int) -> bool:
	var action := world.get_component(id, EcsActionComponent) as EcsActionComponent
	return action != null and action.reached.has(meal) \
		and world.has(meal, EcsPositionComponent)
