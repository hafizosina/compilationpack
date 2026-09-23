class_name EcsPickupSystem
extends EcsSystem

## Takes anything pickable an entity is standing on.
##
## Deciding to go and acting on arrival are different systems, the same split as
## brain and movement: EcsLowBrainSystem never learns what happens when you get
## there, and this never learns why anyone came.
##
## Picking up is **removing `EcsPositionComponent`**. That one line is the whole
## of leaving the world: EcsNodeSyncSystem's query stops matching so the sprite
## stops being drawn, the brain stops seeing anything worth walking to,
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
## **The overlap list is the verdict, and that is a deliberate decision.** This
## used to re-check `distance <= action.radius + item.radius` against the
## components before acting, on the grounds that `reached` describes the end of
## the last physics step and `movement` and `collision` both write positions
## between the sensor stage and this one. But the physics test and that
## arithmetic are *the same condition* — the check was never a stricter rule,
## only the same rule on fresher numbers, and the numbers differ by about a
## pixel: a walker covers 1.2 px in a tick and a settled pair corrects by well
## under one. Against a 48 px reach that is noise.
##
## So reach is now **whatever the physics server last reported**, with an
## accepted error of roughly one tick of motion. The cost is a case that does
## not arise yet: something that jumps position — dropped and re-placed, or
## spawned onto someone — can be taken from where it used to be, for exactly
## one tick. If items ever become droppable, this is the line to revisit.
##
## What is still checked is `EcsPositionComponent`, and that is a different
## question: not "is it near enough" but "is it still in the world at all",
## because something earlier in this same loop may already have taken it.

func label() -> StringName:
	return &"pickup"

func run(world: EcsWorld, _delta: float) -> void:
	for id in world.query([EcsPositionComponent, EcsInventoryComponent, EcsActionComponent]):
		var bag := world.get_component(id, EcsInventoryComponent) as EcsInventoryComponent
		if bag.items.size() >= bag.capacity:
			continue
		var action := world.get_component(id, EcsActionComponent) as EcsActionComponent

		for touched in action.reached:
			if not world.has(touched, EcsPickableComponent):
				continue
			# Something earlier in this same loop may already have taken it.
			if not world.has(touched, EcsPositionComponent):
				continue
			bag.items.append(touched)
			world.remove(touched, EcsPositionComponent)
			if bag.items.size() >= bag.capacity:
				break
