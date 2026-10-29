class_name EcsPickupSystem
extends EcsSystem

## Executes EcsTakeIntentFlag: if the item is still there, unclaimed, in reach
## and the bag has room, stores it as a record and flags the entity dying. With
## a `record_uid`, moves that record out of a lootable entity's bag instead.

func label() -> StringName:
	return &"pickup"

func run(world: EcsWorld, _delta: float) -> void:
	for id in world.query([EcsTakeIntentFlag, EcsPositionComponent,
			EcsInventoryComponent, EcsActionComponent]):
		var intent := world.get_component(id, EcsTakeIntentFlag) as EcsTakeIntentFlag
		var item := intent.target_id
		var bag := world.get_component(id, EcsInventoryComponent) as EcsInventoryComponent
		if bag.items.size() >= bag.capacity:
			continue
		if intent.record_uid != "":
			_loot(world, id, bag, item, intent.record_uid)
			continue
		if not world.is_alive(item) or not world.has(item, EcsPickableComponent):
			continue
		# Already claimed this tick.
		if world.has(item, EcsDyingFlag):
			continue
		var action := world.get_component(id, EcsActionComponent) as EcsActionComponent
		if not action.reached.has(item):
			continue
		bag.items.append(EcsItemRecord.capture(world, item))
		world.add(item, EcsDyingFlag.new())

## Moves the record with `uid` from `source`'s bag into `bag`, if `source` is
## lootable, not dying and in reach.
func _loot(world: EcsWorld, id: int, bag: EcsInventoryComponent, source: int, uid: String) -> void:
	if not world.has(source, EcsLootableComponent) or world.has(source, EcsDyingFlag):
		return
	var action := world.get_component(id, EcsActionComponent) as EcsActionComponent
	if not action.reached.has(source):
		return
	var held := world.get_component(source, EcsInventoryComponent) as EcsInventoryComponent
	if held == null:
		return
	for slot in held.items.size():
		if held.items[slot].uid == uid:
			bag.items.append(held.items[slot])
			held.items.remove_at(slot)
			return
