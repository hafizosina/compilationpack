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
## Picking up is **a death with a record kept**. The item is captured into an
## EcsItemRecord — every component, and its uid — which goes in the bag, and the
## entity is flagged Dying. Next tick the manager destroys it and its nodes, so
## the sprite stops being drawn, the brain stops seeing it and the spawner stops
## counting it, all by the ordinary route every death takes. It used to be
## removing EcsPositionComponent, which left a live entity that was nowhere;
## components now stay fixed from spawn to death, and the item survives as data.
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
## What is still checked is EcsDyingFlag, and that is a different question: not
## "is it near enough" but "is it still anyone's to take" — something earlier in
## this loop, or in EcsConsumeSystem this tick, may already have claimed it.

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
		# Taken earlier in this loop, or eaten earlier this tick: claimed.
		if world.has(item, EcsDyingFlag):
			continue
		var action := world.get_component(id, EcsActionComponent) as EcsActionComponent
		if not action.reached.has(item):
			continue
		# Taking is ending it as an entity and keeping it as data. The flag is
		# the claim, so nobody else can eat or take it for the tick it has left.
		bag.items.append(EcsItemRecord.capture(world, item))
		world.add(item, EcsDyingFlag.new())
