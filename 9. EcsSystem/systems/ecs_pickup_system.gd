class_name EcsPickupSystem
extends EcsSystem

## Takes anything pickable an entity is standing on.
##
## Deciding to go and acting on arrival are different systems, the same split as
## brain and movement: EcsForageSystem never learns what happens when you get
## there, and this never learns why anyone came.
##
## Picking up is **removing `EcsPositionComponent`**. That one line is the whole
## of leaving the world: the render system's query stops matching so the view is
## freed, the forage query stops matching so nobody walks toward it, and the
## spawner stops counting it against its litter cap. Nothing was told to hide
## anything, and there is no `is_carried` flag to keep in step.
##
## Reach is the picker's own body radius — you take what you are standing on.
## An entity with no EcsShapeComponent has no reach and cannot pick anything up.

func label() -> StringName:
	return &"pickup"

func run(world: EcsWorld, _delta: float) -> void:
	var loose := world.query([EcsPositionComponent, EcsPickableComponent])
	if loose.is_empty():
		return

	for id in world.query([EcsPositionComponent, EcsInventoryComponent, EcsShapeComponent]):
		var bag := world.get_component(id, EcsInventoryComponent) as EcsInventoryComponent
		if bag.items.size() >= bag.capacity:
			continue
		var here := (world.get_component(id, EcsPositionComponent) as EcsPositionComponent).position
		var reach := (world.get_component(id, EcsShapeComponent) as EcsShapeComponent).radius

		for berry in loose:
			# `loose` is a snapshot, so something earlier in this same loop may
			# already have taken this one.
			if not world.has(berry, EcsPositionComponent):
				continue
			var there := (world.get_component(berry, EcsPositionComponent) as EcsPositionComponent).position
			if here.distance_to(there) > reach:
				continue

			bag.items.append(berry)
			world.remove(berry, EcsPositionComponent)
			if bag.items.size() >= bag.capacity:
				break
