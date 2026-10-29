class_name EcsDropSystem
extends EcsSystem

## When a carrier dies, puts what it carried back into the world where it
## fell. Must run after every system that can flag a carrier dying.

func label() -> StringName:
	return &"drop"

func run(world: EcsWorld, _delta: float) -> void:
	var inbox := world.get_singleton(EcsLifecycleSingleton) as EcsLifecycleSingleton
	if inbox == null:
		return
	for id in world.query([EcsDyingFlag, EcsInventoryComponent, EcsPositionComponent]):
		var bag := world.get_component(id, EcsInventoryComponent) as EcsInventoryComponent
		if bag.items.is_empty():
			continue
		var here := (world.get_component(id, EcsPositionComponent) as EcsPositionComponent).position
		for record in bag.items:
			var note := EcsSpawnRequest.new()
			note.record = record
			note.position = here
			inbox.spawn_requests.append(note)
		bag.items = []
