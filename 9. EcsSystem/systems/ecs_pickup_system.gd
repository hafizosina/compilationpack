class_name EcsPickupSystem
extends EcsSystem

## Executes EcsTakeIntentFlag: if the item is still there, unclaimed, in reach
## and the bag has room, stores it as a record and flags the entity dying.

func label() -> StringName:
	return &"pickup"

func run(world: EcsWorld, _delta: float) -> void:
	for id in world.query([EcsTakeIntentFlag, EcsPositionComponent,
			EcsInventoryComponent, EcsActionComponent]):
		var item := (world.get_component(id, EcsTakeIntentFlag) as EcsTakeIntentFlag).target_id
		var bag := world.get_component(id, EcsInventoryComponent) as EcsInventoryComponent
		if bag.items.size() >= bag.capacity:
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
