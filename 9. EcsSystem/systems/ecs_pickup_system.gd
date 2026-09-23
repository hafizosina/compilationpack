class_name EcsPickupSystem
extends EcsSystem

## Takes anything pickable an entity is standing on.
##
## Deciding to go and acting on arrival are different systems, the same split as
## brain and movement: EcsForageSystem never learns what happens when you get
## there, and this never learns why anyone came.
##
## Picking up is **removing `EcsPositionComponent`**. That one line is the whole
## of leaving the world: EcsNodeSyncSystem's query stops matching so the sprite
## stops being drawn, the forage query stops matching so nobody walks toward it,
## and the spawner stops counting it against its litter cap. Nothing was told to
## hide anything, and there is no `is_carried` flag to keep in step.
##
## The node itself survives. EcsEntityManager frees nodes only when an entity
## dies, and a berry in a bag is not dead — it is alive and not anywhere. Those
## used to be the same event, because the old render system freed the view the
## tick its query stopped matching. Separating them is what lets the berry be
## put back down again.
##
## **Reach is a real overlap**, not a distance: the ids in the picker's own
## EcsActionComponent.reached are the ones whose body is touching its action
## area as of last tick. An entity with no EcsActionComponent has no reach and
## cannot pick anything up, with no flag saying so.
##
## Make the action radius larger than the entity's own body radius, or it can be
## blocked by the very thing it is reaching for — the two bodies touch and soft
## collision stops it before its reach ever arrives.
##
## **The overlap list culls; the arithmetic below decides.** `reached` is what
## the physics server saw at the end of the last step, so it can name something
## that has since moved — a berry taken and dropped somewhere else is the case
## that caught this — and acting on the list alone would take an item 400 px
## away. So the list narrows the world to a handful of neighbours in C++, and
## one distance check per neighbour confirms it against the components, which
## are the only truth. That is the division of labour the areas were adopted
## for: the cull is what must not be O(n), not the confirmation of three items.

func label() -> StringName:
	return &"pickup"

func run(world: EcsWorld, _delta: float) -> void:
	for id in world.query([EcsPositionComponent, EcsInventoryComponent, EcsActionComponent]):
		var bag := world.get_component(id, EcsInventoryComponent) as EcsInventoryComponent
		if bag.items.size() >= bag.capacity:
			continue
		var action := world.get_component(id, EcsActionComponent) as EcsActionComponent

		var here := (world.get_component(id, EcsPositionComponent) as EcsPositionComponent).position

		for touched in action.reached:
			if not world.has(touched, EcsPickableComponent):
				continue
			# Something earlier in this same loop may already have taken it.
			if not world.has(touched, EcsPositionComponent):
				continue
			var there := (world.get_component(touched, EcsPositionComponent) as EcsPositionComponent).position
			var body := world.get_component(touched, EcsBodyComponent) as EcsBodyComponent
			# Touching means the two circles meet: reach plus the item's own
			# body. Something with no body is a point.
			var touching := action.radius + (body.radius if body != null else 0.0)
			if here.distance_to(there) > touching:
				continue

			bag.items.append(touched)
			world.remove(touched, EcsPositionComponent)
			if bag.items.size() >= bag.capacity:
				break
