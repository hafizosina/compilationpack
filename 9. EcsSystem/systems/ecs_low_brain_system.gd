class_name EcsLowBrainSystem
extends EcsSystem

## The creature's brain: a state machine (IDLE, WANDER, SEEK_FOOD, TAKE, EAT, SLEEP).
## It decides and writes a destination; executors act on the intent flags it
## raises in `_set_state()`.
##
## Each tick: a collapse forces SLEEP; a commitment (SEEK_FOOD) is checked and
## kept or dropped; otherwise it picks the highest rung that applies:
## eat > take > seek food > sleep > wander.

## The view `_food` was built from.
var _food_view: EcsView
## Current food: id -> EcsPositionComponent.
var _food: Dictionary = {}

func label() -> StringName:
	return &"low_brain"

func run(world: EcsWorld, delta: float) -> void:
	_refresh_food(world)
	# Hunger, energy, bag, reach and sensor are optional, so they are looked up.
	var brains := world.view([EcsPositionComponent, EcsMovementComponent, EcsLowBrainComponent])
	var minds := brains.column(EcsLowBrainComponent)
	var moves := brains.column(EcsMovementComponent)
	var places := brains.column(EcsPositionComponent)
	for k in brains.ids.size():
		var id := brains.ids[k]
		var brain := minds[k] as EcsLowBrainComponent
		var move := moves[k] as EcsMovementComponent
		var place := places[k] as EcsPositionComponent

		# Collapsed: forced to sleep, even mid-trip.
		if world.has(id, EcsCollapsedFlag):
			if brain.state != EcsLowBrainComponent.State.SLEEP:
				_abandon_trip(move)
				_set_state(world, id, brain, EcsLowBrainComponent.State.SLEEP)
			continue

		# Asleep: stay down until rested or starving.
		if brain.state == EcsLowBrainComponent.State.SLEEP:
			if not _worth_waking_for(world, id):
				continue
			_release(world, id, brain)

		# Check the current commitment.
		if brain.state == EcsLowBrainComponent.State.SEEK_FOOD:
			if not _is_food(brain.target):
				# Target gone: stop and choose again.
				_abandon_trip(move)
				_release(world, id, brain)
			elif _in_reach(world, id, brain.target):
				# In reach: stop so the rungs below can take or eat it.
				_abandon_trip(move)
				_release(world, id, brain)
			elif not move.has_destination:
				# Trip ended without reaching it.
				_release(world, id, brain)
			else:
				continue

		# Keep walking unless it is only a wander, which may be interrupted.
		if move.has_destination and brain.state != EcsLowBrainComponent.State.WANDER:
			continue

		# Choose, highest rung first.
		if _try_eat(world, id, brain, move):
			continue
		if _try_take(world, id, brain, move):
			continue
		if _try_seek_food(world, id, brain, move, place):
			continue
		if _try_sleep(world, id, brain, move):
			continue
		# Keep wandering.
		if move.has_destination:
			continue
		_wander(world, id, brain, move, place, delta)

## Eat food from the bag or within reach, if hungry enough. Stops any trip.
func _try_eat(world: EcsWorld, id: int, brain: EcsLowBrainComponent,
		move: EcsMovementComponent) -> bool:
	var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent
	if hunger == null or hunger.fullness > hunger.eat_below:
		return false
	# Bag first, then the ground.
	var carried := _meal_in_bag(world, id)
	var meal := EcsWorld.NO_ENTITY if carried != "" else _meal_on_ground(world, id)
	if carried == "" and meal == EcsWorld.NO_ENTITY:
		return false

	_abandon_trip(move)
	_set_state(world, id, brain, EcsLowBrainComponent.State.EAT, meal, carried)
	return true

## The uid of something edible it is carrying, or "".
func _meal_in_bag(world: EcsWorld, id: int) -> String:
	var bag := world.get_component(id, EcsInventoryComponent) as EcsInventoryComponent
	if bag != null:
		for record in bag.items:
			if record.component(EcsConsumableComponent) != null:
				return record.uid
	return ""

## Something edible lying within its action area, or NO_ENTITY.
func _meal_on_ground(world: EcsWorld, id: int) -> int:
	var action := world.get_component(id, EcsActionComponent) as EcsActionComponent
	if action != null:
		for touched in action.reached:
			if _is_food(touched):
				return touched
	return EcsWorld.NO_ENTITY

## Pick up something in reach, if hungry enough to want food and the bag has room.
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

	var item := EcsWorld.NO_ENTITY
	for touched in action.reached:
		if _is_takeable(world, touched):
			item = touched
			break
	if item == EcsWorld.NO_ENTITY:
		return false

	_abandon_trip(move)
	_set_state(world, id, brain, EcsLowBrainComponent.State.TAKE, item)
	return true

## Is `other` in this entity's reach?
func _in_reach(world: EcsWorld, id: int, other: int) -> bool:
	var action := world.get_component(id, EcsActionComponent) as EcsActionComponent
	return action != null and action.reached.has(other)

## Is `id` still on the ground and pickable?
func _is_takeable(world: EcsWorld, id: int) -> bool:
	if id == EcsWorld.NO_ENTITY or not world.is_alive(id):
		return false
	return world.has(id, EcsPickableComponent) and world.has(id, EcsPositionComponent) \
		and not world.has(id, EcsDyingFlag)

## Walk to the nearest food in sight, if hungry enough and the bag has room.
func _try_seek_food(world: EcsWorld, id: int, brain: EcsLowBrainComponent,
		move: EcsMovementComponent, place: EcsPositionComponent) -> bool:
	var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent
	if hunger != null and hunger.fullness > hunger.forage_below:
		return false
	# A full bag stops it; having no bag does not.
	var bag := world.get_component(id, EcsInventoryComponent) as EcsInventoryComponent
	if bag != null and bag.items.size() >= bag.capacity:
		return false
	var sensor := world.get_component(id, EcsSensorComponent) as EcsSensorComponent
	if sensor == null or sensor.perceived.is_empty():
		return false

	var here := place.position
	# Nearest wins.
	var best := EcsWorld.NO_ENTITY
	var best_distance := INF
	for seen in sensor.perceived:
		var there: EcsPositionComponent = _food.get(seen)
		if there == null:
			continue
		var distance := here.distance_squared_to(there.position)
		if distance < best_distance:
			best_distance = distance
			best = seen
	if best == EcsWorld.NO_ENTITY:
		return false

	_set_state(world, id, brain, EcsLowBrainComponent.State.SEEK_FOOD, best)
	_set_trip(move, (_food[best] as EcsPositionComponent).position)
	return true

## Sleep if tired, unless starving.
func _try_sleep(world: EcsWorld, id: int, brain: EcsLowBrainComponent,
		move: EcsMovementComponent) -> bool:
	var energy := world.get_component(id, EcsEnergyComponent) as EcsEnergyComponent
	if energy == null or energy.value > energy.rest_at:
		return false
	if _starving(world, id):
		return false
	_abandon_trip(move)
	_set_state(world, id, brain, EcsLowBrainComponent.State.SLEEP)
	return true

## Wake when rested or starving.
func _worth_waking_for(world: EcsWorld, id: int) -> bool:
	var energy := world.get_component(id, EcsEnergyComponent) as EcsEnergyComponent
	if energy == null or energy.value >= energy.wake_at:
		return true
	return _starving(world, id)

## Fullness at zero.
func _starving(world: EcsWorld, id: int) -> bool:
	var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent
	return hunger != null and hunger.fullness <= 0.0

## Idle for a pause, then wander to a random nearby point.
func _wander(world: EcsWorld, id: int, brain: EcsLowBrainComponent,
		move: EcsMovementComponent, place: EcsPositionComponent, delta: float) -> void:
	_set_state(world, id, brain, EcsLowBrainComponent.State.IDLE)
	brain.pause_left -= delta
	if brain.pause_left > 0.0:
		return
	brain.pause_left = randf_range(brain.pause_min, brain.pause_max)
	_set_state(world, id, brain, EcsLowBrainComponent.State.WANDER)
	_set_trip(move, EcsConst.random_point_near(place.position, brain.radius, 0.25))

## Is `id` currently food on the ground?
func _is_food(id: int) -> bool:
	return _food.has(id)

## Rebuilds `_food` when the food view changes.
func _refresh_food(world: EcsWorld) -> void:
	var food := world.view([EcsConsumableComponent, EcsPositionComponent], [EcsDyingFlag])
	if food == _food_view:
		return
	_food_view = food
	_food = {}
	var places := food.column(EcsPositionComponent)
	for k in food.ids.size():
		_food[food.ids[k]] = places[k]

## Back to IDLE. Does not touch the trip.
func _release(world: EcsWorld, id: int, brain: EcsLowBrainComponent) -> void:
	_set_state(world, id, brain, EcsLowBrainComponent.State.IDLE)

## The only place `state` and `target` are written. Clears the old state's flag
## and raises the new one's, so the flags always match the state.
func _set_state(world: EcsWorld, id: int, brain: EcsLowBrainComponent,
		state: EcsLowBrainComponent.State, target: int = EcsWorld.NO_ENTITY,
		record_uid: String = "") -> void:
	if brain.state == state and brain.target == target:
		var eating := world.get_component(id, EcsEatIntentFlag) as EcsEatIntentFlag
		if eating != null:
			eating.record_uid = record_uid
		return
	var old_flag: Script = _flag_for(brain.state)
	if old_flag != null:
		world.remove(id, old_flag)
	brain.state = state
	brain.target = target
	match state:
		EcsLowBrainComponent.State.EAT:
			var eat := EcsEatIntentFlag.new()
			eat.target_id = target
			eat.record_uid = record_uid
			world.add(id, eat)
		EcsLowBrainComponent.State.TAKE:
			var take := EcsTakeIntentFlag.new()
			take.target_id = target
			world.add(id, take)
		EcsLowBrainComponent.State.SLEEP:
			world.add(id, EcsAsleepFlag.new())

## The flag a state raises, or null.
static func _flag_for(state: EcsLowBrainComponent.State) -> Script:
	match state:
		EcsLowBrainComponent.State.EAT:
			return EcsEatIntentFlag
		EcsLowBrainComponent.State.TAKE:
			return EcsTakeIntentFlag
		EcsLowBrainComponent.State.SLEEP:
			return EcsAsleepFlag
	return null

## Sets a destination. Zeroes `time_left` so the trip gets a fresh time budget.
func _set_trip(move: EcsMovementComponent, point: Vector2) -> void:
	move.destination = point
	move.has_destination = true
	move.time_left = 0.0

## Cancels the current trip.
func _abandon_trip(move: EcsMovementComponent) -> void:
	move.has_destination = false
	move.velocity = Vector2.ZERO
	move.time_left = 0.0
