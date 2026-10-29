class_name EcsLowBrainSystem
extends EcsSystem

## The creature's brain: a state machine (IDLE, WANDER, SEEK_FOOD, TAKE, EAT, SLEEP,
## HUNT, ATTACK, HARVEST).
## It decides and writes a destination; executors act on the intent flags it
## raises in `_set_state()`.
##
## Each tick: a collapse forces SLEEP; a commitment (SEEK_FOOD, HUNT, ATTACK) is
## checked and kept or dropped (food in sight ends a hunt); otherwise it picks the
## highest rung that applies: eat > take (or loot) > seek food > harvest > hunt > sleep >
## wander. Food is filtered by diet: a creature only eats, seeks and harvests what its
## hunger `eats`.

## The view `_food` was built from.
var _food_view: EcsView
## Current food: id -> EcsPositionComponent.
var _food: Dictionary = {}
## Current food: id -> its diet.
var _diet: Dictionary = {}
## The view `_bushes` was built from.
var _bush_view: EcsView
## Current harvestables: id -> EcsHarvestableComponent.
var _bushes: Dictionary = {}
## Current harvestables: id -> EcsPositionComponent.
var _bush_at: Dictionary = {}

func label() -> StringName:
	return &"low_brain"

func run(world: EcsWorld, delta: float) -> void:
	_refresh_food(world)
	_refresh_bushes(world)
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
			if not _is_food(brain.target) and not _has_stock(brain.target):
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

		if brain.state == EcsLowBrainComponent.State.HUNT \
				or brain.state == EcsLowBrainComponent.State.ATTACK:
			if _keep_hunting(world, id, brain, move):
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
		if _try_harvest(world, id, brain, move, place):
			continue
		if _try_hunt(world, id, brain, move, place):
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
	var carried := _meal_in_bag(world, id, hunger)
	var meal := EcsWorld.NO_ENTITY if carried != "" else _meal_on_ground(world, id, hunger)
	if carried == "" and meal == EcsWorld.NO_ENTITY:
		return false

	_abandon_trip(move)
	_set_state(world, id, brain, EcsLowBrainComponent.State.EAT, meal, carried)
	return true

## The uid of something it carries and eats, or "".
func _meal_in_bag(world: EcsWorld, id: int, hunger: EcsHungerComponent) -> String:
	var bag := world.get_component(id, EcsInventoryComponent) as EcsInventoryComponent
	if bag != null:
		for record in bag.items:
			var food := record.component(EcsConsumableComponent) as EcsConsumableComponent
			if food != null and food.diet == hunger.eats:
				return record.uid
	return ""

## Something it eats lying within its action area, or NO_ENTITY.
func _meal_on_ground(world: EcsWorld, id: int, hunger: EcsHungerComponent) -> int:
	var action := world.get_component(id, EcsActionComponent) as EcsActionComponent
	if action != null:
		for touched in action.reached:
			if _edible(touched, hunger):
				return touched
	return EcsWorld.NO_ENTITY

## Pick up something in reach, or loot a record from a lootable entity in
## reach, if hungry enough to want food and the bag has room.
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
	var record_uid := ""
	for touched in action.reached:
		if _is_takeable(world, touched):
			item = touched
			break
		record_uid = _loot_in(world, touched)
		if record_uid != "":
			item = touched
			break
	if item == EcsWorld.NO_ENTITY:
		return false

	_abandon_trip(move)
	_set_state(world, id, brain, EcsLowBrainComponent.State.TAKE, item, record_uid)
	return true

## The uid of a record that can be looted from `id`, or "".
func _loot_in(world: EcsWorld, id: int) -> String:
	if not world.has(id, EcsLootableComponent) or world.has(id, EcsDyingFlag):
		return ""
	var held := world.get_component(id, EcsInventoryComponent) as EcsInventoryComponent
	if held == null or held.items.is_empty():
		return ""
	return held.items[0].uid

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

## Hungry enough to forage, and the bag (if any) has room.
func _foraging(world: EcsWorld, id: int, hunger: EcsHungerComponent) -> bool:
	if hunger != null and hunger.fullness > hunger.forage_below:
		return false
	# A full bag stops it; having no bag does not.
	var bag := world.get_component(id, EcsInventoryComponent) as EcsInventoryComponent
	return bag == null or bag.items.size() < bag.capacity

## Walk to the nearest food in sight, if foraging.
func _try_seek_food(world: EcsWorld, id: int, brain: EcsLowBrainComponent,
		move: EcsMovementComponent, place: EcsPositionComponent) -> bool:
	var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent
	if not _foraging(world, id, hunger):
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
		if there == null or not _edible(seen, hunger):
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

## Harvest a plant in reach, or walk to the nearest one in sight, if foraging.
func _try_harvest(world: EcsWorld, id: int, brain: EcsLowBrainComponent,
		move: EcsMovementComponent, place: EcsPositionComponent) -> bool:
	if _bushes.is_empty():
		return false
	var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent
	if not _foraging(world, id, hunger):
		return false
	var action := world.get_component(id, EcsActionComponent) as EcsActionComponent
	if action != null:
		for touched in action.reached:
			if _harvestable(touched, hunger):
				_abandon_trip(move)
				_set_state(world, id, brain, EcsLowBrainComponent.State.HARVEST, touched)
				return true
	var sensor := world.get_component(id, EcsSensorComponent) as EcsSensorComponent
	if sensor == null:
		return false

	var best := EcsWorld.NO_ENTITY
	var best_distance := INF
	for seen in sensor.perceived:
		if not _harvestable(seen, hunger):
			continue
		var there := (_bush_at[seen] as EcsPositionComponent).position
		var distance := place.position.distance_squared_to(there)
		if distance < best_distance:
			best_distance = distance
			best = seen
	if best == EcsWorld.NO_ENTITY:
		return false

	_set_state(world, id, brain, EcsLowBrainComponent.State.SEEK_FOOD, best)
	_set_trip(move, (_bush_at[best] as EcsPositionComponent).position)
	return true

## Is `id` a plant with stock left?
func _has_stock(id: int) -> bool:
	var crop: EcsHarvestableComponent = _bushes.get(id)
	return crop != null and crop.stock > 0

## Is `id` a plant with stock whose yield this hunger eats? Without hunger, any.
func _harvestable(id: int, hunger: EcsHungerComponent) -> bool:
	return _has_stock(id) and (hunger == null
		or (_bushes[id] as EcsHarvestableComponent).diet == hunger.eats)

## Chase the nearest prey in sight, if it can attack and is hungry enough.
## Prey is anything with health that is not dying and not its own kind.
func _try_hunt(world: EcsWorld, id: int, brain: EcsLowBrainComponent,
		move: EcsMovementComponent, place: EcsPositionComponent) -> bool:
	if not world.has(id, EcsDamageComponent):
		return false
	var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent
	if hunger != null and hunger.fullness > hunger.forage_below:
		return false
	var sensor := world.get_component(id, EcsSensorComponent) as EcsSensorComponent
	if sensor == null:
		return false

	var best := EcsWorld.NO_ENTITY
	var best_distance := INF
	for seen in sensor.perceived:
		if not _is_prey(world, id, seen):
			continue
		var there := (world.get_component(seen, EcsPositionComponent) as EcsPositionComponent).position
		var distance := place.position.distance_squared_to(there)
		if distance < best_distance:
			best_distance = distance
			best = seen
	if best == EcsWorld.NO_ENTITY:
		return false

	_set_state(world, id, brain, EcsLowBrainComponent.State.HUNT, best)
	_set_trip(move, _position_of(world, best))
	return true

## Follows a HUNT or ATTACK commitment. Returns false once it ends, so the
## rungs can choose again this tick.
func _keep_hunting(world: EcsWorld, id: int, brain: EcsLowBrainComponent,
		move: EcsMovementComponent) -> bool:
	var prey := brain.target
	if not _is_prey(world, id, prey) or _sees_food(world, id):
		# Dead, dying or gone, or there is food to eat instead.
		_abandon_trip(move)
		_release(world, id, brain)
		return false
	if _in_reach(world, id, prey):
		_abandon_trip(move)
		_set_state(world, id, brain, EcsLowBrainComponent.State.ATTACK, prey)
		return true
	if brain.state == EcsLowBrainComponent.State.ATTACK:
		# It got away: chase again.
		_set_state(world, id, brain, EcsLowBrainComponent.State.HUNT, prey)
		_set_trip(move, _position_of(world, prey))
		return true
	if not move.has_destination:
		# Out of time; give up.
		_release(world, id, brain)
		return false
	# Follow it, on the same time budget.
	move.destination = _position_of(world, prey)
	return true

## Is there food it eats in sight?
func _sees_food(world: EcsWorld, id: int) -> bool:
	var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent
	var sensor := world.get_component(id, EcsSensorComponent) as EcsSensorComponent
	if sensor == null:
		return false
	for seen in sensor.perceived:
		if _edible(seen, hunger):
			return true
	return false

## Can `id` hunt `other`?
func _is_prey(world: EcsWorld, id: int, other: int) -> bool:
	if other == id or not world.has(other, EcsHealthComponent) \
			or not world.has(other, EcsPositionComponent) or world.has(other, EcsDyingFlag):
		return false
	var mine := world.get_component(id, EcsNameComponent) as EcsNameComponent
	var theirs := world.get_component(other, EcsNameComponent) as EcsNameComponent
	return mine == null or theirs == null or mine.type_id != theirs.type_id

func _position_of(world: EcsWorld, id: int) -> Vector2:
	return (world.get_component(id, EcsPositionComponent) as EcsPositionComponent).position

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

## Is `id` food on the ground that this hunger eats? Without hunger, any food.
func _edible(id: int, hunger: EcsHungerComponent) -> bool:
	return _food.has(id) and (hunger == null or _diet[id] == hunger.eats)

## Rebuilds `_food` when the food view changes.
func _refresh_food(world: EcsWorld) -> void:
	var food := world.view([EcsConsumableComponent, EcsPositionComponent], [EcsDyingFlag])
	if food == _food_view:
		return
	_food_view = food
	_food = {}
	_diet = {}
	var places := food.column(EcsPositionComponent)
	var foods := food.column(EcsConsumableComponent)
	for k in food.ids.size():
		_food[food.ids[k]] = places[k]
		_diet[food.ids[k]] = (foods[k] as EcsConsumableComponent).diet

## Rebuilds `_bushes` when the harvestable view changes.
func _refresh_bushes(world: EcsWorld) -> void:
	var plants := world.view([EcsHarvestableComponent, EcsPositionComponent], [EcsDyingFlag])
	if plants == _bush_view:
		return
	_bush_view = plants
	_bushes = {}
	_bush_at = {}
	var crops := plants.column(EcsHarvestableComponent)
	var places := plants.column(EcsPositionComponent)
	for k in plants.ids.size():
		_bushes[plants.ids[k]] = crops[k]
		_bush_at[plants.ids[k]] = places[k]

## Back to IDLE. Does not touch the trip.
func _release(world: EcsWorld, id: int, brain: EcsLowBrainComponent) -> void:
	_set_state(world, id, brain, EcsLowBrainComponent.State.IDLE)

## The only place `state` and `target` are written. Clears the old state's flag
## and raises the new one's, so the flags always match the state.
func _set_state(world: EcsWorld, id: int, brain: EcsLowBrainComponent,
		state: EcsLowBrainComponent.State, target: int = EcsWorld.NO_ENTITY,
		record_uid: String = "") -> void:
	if brain.state == state and brain.target == target:
		# Same target, maybe a different record: refresh the uid.
		var eating := world.get_component(id, EcsEatIntentFlag) as EcsEatIntentFlag
		if eating != null:
			eating.record_uid = record_uid
		var taking := world.get_component(id, EcsTakeIntentFlag) as EcsTakeIntentFlag
		if taking != null:
			taking.record_uid = record_uid
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
			take.record_uid = record_uid
			world.add(id, take)
		EcsLowBrainComponent.State.SLEEP:
			world.add(id, EcsAsleepFlag.new())
		EcsLowBrainComponent.State.ATTACK:
			var attack := EcsAttackIntentFlag.new()
			attack.target_id = target
			world.add(id, attack)
		EcsLowBrainComponent.State.HARVEST:
			var harvest := EcsHarvestIntentFlag.new()
			harvest.target_id = target
			world.add(id, harvest)

## The flag a state raises, or null.
static func _flag_for(state: EcsLowBrainComponent.State) -> Script:
	match state:
		EcsLowBrainComponent.State.EAT:
			return EcsEatIntentFlag
		EcsLowBrainComponent.State.TAKE:
			return EcsTakeIntentFlag
		EcsLowBrainComponent.State.SLEEP:
			return EcsAsleepFlag
		EcsLowBrainComponent.State.ATTACK:
			return EcsAttackIntentFlag
		EcsLowBrainComponent.State.HARVEST:
			return EcsHarvestIntentFlag
	return null

## Sets a destination. Zeroes `time_left` so the trip gets a fresh time budget.
## The one other destination write is `_keep_hunting` following moving prey,
## which keeps the budget on purpose.
func _set_trip(move: EcsMovementComponent, point: Vector2) -> void:
	move.destination = point
	move.has_destination = true
	move.time_left = 0.0

## Cancels the current trip.
func _abandon_trip(move: EcsMovementComponent) -> void:
	move.has_destination = false
	move.velocity = Vector2.ZERO
	move.time_left = 0.0
