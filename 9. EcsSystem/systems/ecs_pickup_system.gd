class_name EcsPickupSystem
extends EcsSystem

## Carries out the decision to take something. It does not make it.
##
## `EcsLowBrainSystem` raises EcsTakeIntentFlag, naming the item, when it wants
## something its action area is touching; this moves that thing into the bag.
## It reads the flag and never the brain, so anything that raises it drives this. Deciding and
## acting are different systems, the same split as brain and movement, and the
## same one EcsConsumeSystem is the other half of.
##
## **It used to be a reflex.** This ran over anything with a bag and an action
## area and took whatever it touched, whether or not the creature had any reason
## to — a full monkey hoovered up every berry it wandered across, and nothing
## had decided that. Eating was already a decision by then, so taking being a
## reflex was an inconsistency rather than a design: the brain is the only thing
## in this module that chooses, and now it chooses this too.
##
## It stayed a system rather than folding into the brain, which would have been
## fifteen lines shorter. Three reasons. The brain would begin mutating *another
## entity's* components — the berry's position — which is the line that keeps it
## from growing hands. The same argument would then merge EcsConsumeSystem too,
## and every verb after it, which is the god-object this module was built away
## from. And step 7's planner emits a sequence of action ids that wants exactly
## one executor per action, so a merge now is a split again later.
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
	for id in world.query([EcsTakeIntentFlag, EcsPositionComponent,
			EcsInventoryComponent, EcsActionComponent]):
		# Nothing happens unless something decided it. The flag is in the query
		# because "taking is a decision" has no sensible exception: a thing with
		# a bag and no intent would be picking up on nobody's authority, which
		# is the reflex this stopped being.
		var item := (world.get_component(id, EcsTakeIntentFlag) as EcsTakeIntentFlag).target_id
		var bag := world.get_component(id, EcsInventoryComponent) as EcsInventoryComponent
		if bag.items.size() >= bag.capacity:
			continue
		if not world.is_alive(item) or not world.has(item, EcsPickableComponent):
			continue
		# Something earlier in this same loop may already have taken it.
		if not world.has(item, EcsPositionComponent):
			continue
		# Or eaten it, earlier this tick: it is claimed and dies next tick.
		if world.has(item, EcsDyingFlag):
			continue
		var action := world.get_component(id, EcsActionComponent) as EcsActionComponent
		if not action.reached.has(item):
			continue
		bag.items.append(item)
		world.remove(item, EcsPositionComponent)
