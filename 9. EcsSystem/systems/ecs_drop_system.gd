class_name EcsDropSystem
extends EcsSystem

## When a carrier dies, what it carried goes back into the world, where it fell.
##
## Before this, nothing handled a bag on death: a dead monkey's berries stayed
## alive forever with no position and nobody holding them. Now a carried item is
## an EcsItemRecord, and for every entity flagged Dying that has a bag and a
## place, this writes one spawn note per record at that place. The lifecycle
## stage builds each from its record — the same berry, its instance values and
## uid intact, a new id — at the same instant it destroys the carrier.
##
## Berries are not solid, so several put back on one spot simply stack there.
## They belong to no bush, so they count against no litter cap.
##
## It runs late in the pipeline, after everything that can kill a carrier, so a
## death flagged anywhere earlier in the tick is covered. A system that flags a
## carrier Dying must run before this one, or the bag dies with it. The bag is
## emptied as it is dropped, so nothing can drop twice.
##
## For a real game, death by health will leave a corpse to loot instead, and
## this is the path that will build on.

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
