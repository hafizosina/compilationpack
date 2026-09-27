class_name EcsLowBrainSystem
extends EcsSystem

## The creature's brain: one state machine, one place to read a decision.
##
## It reads the world and writes a destination into EcsMovementComponent. That
## is still the only thing it says to the rest of the pipeline — movement,
## collision and node_sync are as unaware of brains as they ever were, and a
## planner replacing this at step 7 changes nothing downstream.
##
## ## Why one system and not a rung each
##
## Deciding used to be split: EcsForageSystem wrote a destination toward food,
## this one wrote a destination to wander to, and priority was the order the two
## sat in the scheduler. That is a genuinely nice property — a rung was one file
## and one scheduler line, and neither existing rung changed when a third
## arrived — but it bought it with statelessness, and three things fall out of
## that which a creature needs:
##
##   - **Persistence.** "I am going to that berry" had nowhere to live, so it
##     was re-derived every tick from whatever the sensor happened to report.
##   - **Preemption.** A rung could only fill an *empty* destination slot. A
##     wolf appearing mid-forage could not interrupt, because every rung
##     politely skips an entity that already has somewhere to be.
##   - **Hysteresis.** A threshold sitting near its trigger flickers the
##     creature between rungs on consecutive ticks, because nothing remembers
##     which side it was on last — and step 4's hunger thresholds are exactly
##     that shape, which is what forced the issue.
##
## So the rungs moved inside one function, where the ladder is the order of the
## branches and the state is a field. The priority is no less explicit for being
## a sequence of `if`s — it is arguably more so, since the whole decision reads
## top to bottom in one place instead of across two files and a scheduler.
##
## The cost, stated plainly: this system reads components that are not its own
## (sensor, inventory) and will read more as behaviours arrive, so it is the one
## place in the module that knows about several concerns at once. That is what a
## brain is. The line it must not cross is *doing* anything with them — it still
## writes nothing but `state`, `target`, `pause_left` and a destination.
##
## ## The shape of a tick
##
## Validate the standing commitment, then — only if there is no commitment left
## — decide again, highest rung first. A creature that is mid-trip falls out at
## the first or second check and costs almost nothing.

func label() -> StringName:
	return &"low_brain"

func run(world: EcsWorld, delta: float) -> void:
	for id in world.query([EcsPositionComponent, EcsMovementComponent, EcsLowBrainComponent]):
		var brain := world.get_component(id, EcsLowBrainComponent) as EcsLowBrainComponent
		var move := world.get_component(id, EcsMovementComponent) as EcsMovementComponent

		# 0. Collapsed: it has no say at all. This is above the commitment check
		# on purpose — dropping from exhaustion overrides a trip already under
		# way, which nothing else in this brain is allowed to do.
		if world.has(id, EcsCollapsedFlag):
			if brain.state != EcsLowBrainComponent.State.SLEEP:
				_release(brain)
				_abandon_trip(move)
				brain.state = EcsLowBrainComponent.State.SLEEP
			continue

		# 0b. Sleeping by choice: stay down until rested, or until starving.
		if brain.state == EcsLowBrainComponent.State.SLEEP:
			if not _worth_waking_for(world, id):
				continue
			_release(brain)

		# 1. Does the standing commitment still hold?
		if brain.state == EcsLowBrainComponent.State.SEEK_FOOD:
			if not _is_food(world, brain.target):
				# The thing it was going to is gone — eaten, taken, killed. It
				# is walking to a spot with nothing in it, so take the trip off
				# it and let it choose again this same tick. *This* is what the
				# state was for: the old stateless rung could only fill an empty
				# destination slot, never take a full one, so a forager whose
				# berry was stolen walked to the empty grass anyway.
				_abandon_trip(move)
				_release(brain)
			elif _in_reach(world, id, brain.target):
				# Close enough to touch it, which is what it set out for. The
				# trip's destination is the berry's *centre*, so waiting for
				# the trip to end would walk it onto the thing before taking
				# it — fulfilling a commitment is not reconsidering one, so the
				# rungs below get to act this same tick.
				_abandon_trip(move)
				_release(brain)
			elif not move.has_destination:
				# The trip ended without arriving: given up, or the target was
				# taken and re-placed out of reach. Either way it is no longer
				# seeking, and whether it got anything is not this brain's
				# business to ask.
				_release(brain)
			else:
				continue

		# 2. A commitment is not reconsidered; a wander is. This is the whole
		# difference state makes. A creature that is walking nowhere in
		# particular should be free to notice a berry *this* tick rather than
		# when its aimless leg happens to end — and without a state field there
		# was no way to tell those two trips apart, so neither could be
		# interrupted and both ran to completion.
		if move.has_destination and brain.state != EcsLowBrainComponent.State.WANDER:
			continue

		# 3. Choose, highest rung first.
		if _try_eat(world, id, brain, move):
			continue
		if _try_take(world, id, brain, move):
			continue
		if _try_seek_food(world, id, brain, move):
			continue
		if _try_sleep(world, id, brain, move):
			continue
		# Nothing better came up, so an existing wander simply carries on.
		if move.has_destination:
			continue
		_wander(world, id, brain, move, delta)

## Rung 1 — eat what it is already carrying, if it is hungry enough.
##
## Above fetching on purpose: a creature with food in its bag has no business
## walking across the arena for more. It only *decides* here — the berry leaves
## the bag in EcsConsumeSystem, which runs straight after this one and reads the
## EAT state as its instruction. The brain deciding and a system acting is the
## same split the module runs on everywhere, and it is what stops this file
## growing hands.
##
## Eating stands still, so any trip in progress is called off. There is no
## commitment to hold: the decision is re-made next tick from whatever hunger
## and the food at hand then say, which is what lets one bite per tick add up
## to a meal.
##
## **A bag is one way to have food at hand, not the only one.** A carrier eats
## out of its inventory; a grazer with no EcsInventoryComponent at all eats what
## its action area is touching, off the ground, where it stands. Both are "there
## is food within reach", and neither is a special case of the other — which is
## why this asks that question rather than asking about a bag.
##
## Reach itself is decided by the physics server and taken at its word, to
## within about a tick of motion. What this and EcsConsumeSystem both re-ask is
## the other question — whether the thing named is still in the world at all,
## since it may have been eaten or pocketed since the list was written.
func _try_eat(world: EcsWorld, id: int, brain: EcsLowBrainComponent,
		move: EcsMovementComponent) -> bool:
	var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent
	if hunger == null or hunger.fullness > hunger.eat_below:
		return false
	if not _food_at_hand(world, id):
		return false

	_release(brain)
	_abandon_trip(move)
	brain.state = EcsLowBrainComponent.State.EAT
	return true

## Is there something edible it could put in its mouth right now — carried, or
## lying under its nose?
func _food_at_hand(world: EcsWorld, id: int) -> bool:
	var bag := world.get_component(id, EcsInventoryComponent) as EcsInventoryComponent
	if bag != null:
		for item in bag.items:
			if world.has(item, EcsConsumableComponent):
				return true
	var action := world.get_component(id, EcsActionComponent) as EcsActionComponent
	if action != null:
		for touched in action.reached:
			if _is_food(world, touched):
				return true
	return false

## Rung 2 — put something within reach into the bag.
##
## Taking used to happen without anyone deciding it. EcsPickupSystem ran over
## anything with a bag and an action area and took whatever it touched, so a
## perfectly full monkey hoovered up every berry it wandered across. That was a
## reflex, and the module had settled that the brain is the only thing that
## chooses — so it is a rung now, and pickup does nothing until it fires.
##
## Gated on the same `forage_below` that sends it out in the first place: a
## creature wants a berry for one reason, and a fed one has no more business
## pocketing food than it has walking to it. Eating outranks this, so a hungry
## creature standing over a berry eats it where it lies rather than bagging it
## first — bagging is for when you are peckish now and hungry later.
##
## Having no EcsInventoryComponent is the whole of "cannot carry": a rabbit
## never takes the rung, and no flag says so.
##
## It only decides. The berry moves in EcsPickupSystem, which reads TAKE as its
## instruction exactly as EcsConsumeSystem reads EAT — and which stays a system
## of its own because step 7's planner emits action ids that need one executor
## each. Standing still to do it, so any wander in progress is called off.
func _try_take(world: EcsWorld, id: int, brain: EcsLowBrainComponent,
		move: EcsMovementComponent) -> bool:
	var bag := world.get_component(id, EcsInventoryComponent) as EcsInventoryComponent
	if bag == null or bag.items.size() >= bag.capacity:
		return false
	var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent
	if hunger != null and hunger.fullness > hunger.forage_below:
		return false
	var action := world.get_component(id, EcsActionComponent) as EcsActionComponent
	if action == null:
		return false

	var takeable := false
	for touched in action.reached:
		if _is_takeable(world, touched):
			takeable = true
			break
	if not takeable:
		return false

	_release(brain)
	_abandon_trip(move)
	brain.state = EcsLowBrainComponent.State.TAKE
	return true

## Is `other` close enough for this entity to act on?
##
## The physics server's answer, taken at its word — the same reading
## EcsPickupSystem and EcsConsumeSystem act on, so the brain cannot decide to
## take something they will then decline to reach.
func _in_reach(world: EcsWorld, id: int, other: int) -> bool:
	var action := world.get_component(id, EcsActionComponent) as EcsActionComponent
	return action != null and action.reached.has(other)

## Is `id` something that could go in a bag, and still there to be put in one?
##
## Pickable rather than consumable: what a bag will hold is a wider question
## than what a mouth will, and the day a tool exists this rung should want it
## while the eat rung still does not.
func _is_takeable(world: EcsWorld, id: int) -> bool:
	if id == EcsWorld.NO_ENTITY or not world.is_alive(id):
		return false
	return world.has(id, EcsPickableComponent) and world.has(id, EcsPositionComponent)

## Rung 3 — go and get a berry, if it is hungry enough and has room to put one.
##
## The candidates are the ids in the entity's own EcsSensorComponent.perceived:
## what its sensor area overlapped last tick. A berry across the map does not
## exist as far as this rung is concerned, and that is what keeps it from being
## O(foragers x berries) — the broadphase culls to a handful of neighbours in
## C++ and the ranking below sorts those few.
##
## Sensor and inventory are read through `get_component` rather than named in
## the query, because they are what make this rung *possible*, not what makes
## the brain possible: a creature with no sensor simply never takes it, and
## needs no flag saying so.
func _try_seek_food(world: EcsWorld, id: int, brain: EcsLowBrainComponent,
		move: EcsMovementComponent) -> bool:
	# The motive. Without this the rung is motion with no reason — it gathered
	# because it could, and stopped only when the bag filled. A creature below
	# its forage threshold now wanders past food it can plainly see.
	var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent
	if hunger != null and hunger.fullness > hunger.forage_below:
		return false
	# A bag caps how much it may fetch; having none does not stop it going.
	# A grazer walks to the berry and eats it where it lies.
	var bag := world.get_component(id, EcsInventoryComponent) as EcsInventoryComponent
	if bag != null and bag.items.size() >= bag.capacity:
		return false
	var sensor := world.get_component(id, EcsSensorComponent) as EcsSensorComponent
	if sensor == null or sensor.perceived.is_empty():
		return false

	var here := (world.get_component(id, EcsPositionComponent) as EcsPositionComponent).position
	# Nearest of what it can see wins. Squared distance: ranking needs the
	# order, never the number, so it does not pay for the square root.
	var best := EcsWorld.NO_ENTITY
	var best_distance := INF
	for seen in sensor.perceived:
		if not _is_food(world, seen):
			continue
		var there := (world.get_component(seen, EcsPositionComponent) as EcsPositionComponent).position
		var distance := here.distance_squared_to(there)
		if distance < best_distance:
			best_distance = distance
			best = seen
	if best == EcsWorld.NO_ENTITY:
		return false

	brain.target = best
	brain.state = EcsLowBrainComponent.State.SEEK_FOOD
	_set_trip(move, (world.get_component(best, EcsPositionComponent) as EcsPositionComponent).position)
	return true

## Rung 4 — lie down, if nothing above wanted anything.
##
## Below the food rungs deliberately: a tired, hungry creature that can see a
## berry goes for it, and only one with nothing in sight sleeps. A creature that
## keeps finding food can therefore run itself to collapse, which is the price
## of food outranking rest rather than a bug.
##
## Entering sleep only ever happens from IDLE or WANDER, because a SEEK_FOOD
## commitment is not reconsidered — the one thing that overrides it is a
## collapse, handled above. The trip is called off through the same helper as
## everything else, so the clock is zeroed and movement, which is told nothing,
## simply finds no destination and stops.
func _try_sleep(world: EcsWorld, id: int, brain: EcsLowBrainComponent,
		move: EcsMovementComponent) -> bool:
	var energy := world.get_component(id, EcsEnergyComponent) as EcsEnergyComponent
	if energy == null or energy.value > energy.rest_at:
		return false
	if _starving(world, id):
		# Too hungry to lie down. Without this a starving creature woken by its
		# stomach would be put straight back to sleep by this rung while it is
		# still tired, and starve where it lay.
		return false
	_release(brain)
	_abandon_trip(move)
	brain.state = EcsLowBrainComponent.State.SLEEP
	return true

## Is there anything worth getting up for? Rested is the ordinary end of a
## sleep; starving is the interruption — the first thing in this module that
## preempts a standing state rather than filling an empty slot.
func _worth_waking_for(world: EcsWorld, id: int) -> bool:
	var energy := world.get_component(id, EcsEnergyComponent) as EcsEnergyComponent
	if energy == null or energy.value >= energy.wake_at:
		return true
	return _starving(world, id)

## Empty, with nothing left to draw on. The same condition EcsHungerSystem
## spends health on, asked here so the two never disagree about what starving
## is — and it is the only thing that outranks being tired.
func _starving(world: EcsWorld, id: int) -> bool:
	var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent
	return hunger != null and hunger.fullness <= 0.0

## Rung 5, and the floor — drift somewhere nearby, having rested first.
##
## The pause clock runs only here, which is why a creature that spent ten
## seconds walking to a berry does not then owe ten seconds of accumulated
## rest: its pause starts when it has nothing to do.
func _wander(world: EcsWorld, id: int, brain: EcsLowBrainComponent,
		move: EcsMovementComponent, delta: float) -> void:
	brain.state = EcsLowBrainComponent.State.IDLE
	brain.pause_left -= delta
	if brain.pause_left > 0.0:
		return
	brain.pause_left = randf_range(brain.pause_min, brain.pause_max)
	var here := world.get_component(id, EcsPositionComponent) as EcsPositionComponent
	brain.state = EcsLowBrainComponent.State.WANDER
	_set_trip(move, EcsConst.random_point_near(here.position, brain.radius, 0.25))

## Is `id` still food that is somewhere?
##
## Consumable and not merely pickable: since hunger became the motive, the food
## rung wants *food*, and a future carryable that is not edible — a tool, a
## stick — must not be chased by a hungry animal. Whether it can also be carried
## away is EcsPickupSystem's question, asked separately and for its own reasons.
##
## A berry someone else took this tick has lost its EcsPositionComponent and is
## no longer anywhere; one that was eaten is not alive at all. The sensor's
## overlap list is a tick behind and can still name either, so *existence* is
## re-asked of the components before anything is committed to. How far away it
## is, by contrast, is the physics server's answer and is not second-guessed.
func _is_food(world: EcsWorld, id: int) -> bool:
	if id == EcsWorld.NO_ENTITY or not world.is_alive(id):
		return false
	return world.has(id, EcsConsumableComponent) and world.has(id, EcsPositionComponent)

## Ends a commitment. Only the brain's own fields — whether the trip it implied
## is also called off is a separate decision, made above.
func _release(brain: EcsLowBrainComponent) -> void:
	brain.target = EcsWorld.NO_ENTITY
	brain.state = EcsLowBrainComponent.State.IDLE

## Sends an entity to a spot — the only place this system writes a destination.
##
## Zeroing `time_left` is not optional. EcsMovementSystem prices a trip on the
## tick it first sees one and reads a non-zero clock as "already priced", so a
## destination written over a trip already in progress would inherit whatever
## was left of the old budget and time out early. Routing every write through
## here is what makes overwriting a live destination safe, which is what
## preemption is.
func _set_trip(move: EcsMovementComponent, point: Vector2) -> void:
	move.destination = point
	move.has_destination = true
	move.time_left = 0.0

## Calls off a trip in progress — the reason a brain with state can do something
## the old stateless rungs could not.
func _abandon_trip(move: EcsMovementComponent) -> void:
	move.has_destination = false
	move.velocity = Vector2.ZERO
	move.time_left = 0.0
