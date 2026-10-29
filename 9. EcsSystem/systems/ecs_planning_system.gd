class_name EcsPlanningSystem
extends EcsSystem

## Chooses each planner's goal by utility and plans the route to it. Writes only
## EcsPlannerComponent; the brain executes the first step.
##
## Each run it snapshots facts and ranks goals for every planner. A planner is
## queued for a replan only when its facts or its ranking changed; at most
## MAX_REPLANS are planned per run, oldest first. Planning goes through goals in
## rank order until one has a plan.

## Replans per run.
const MAX_REPLANS: int = 64
## Below its gate a need scores at least this fraction of its weight.
const FLOOR: float = 0.6
## Added to the current goal's score, so near-ties don't flicker.
const COMMIT_BONUS: float = 0.5

## Ids waiting for a replan, oldest first.
var _queue: Array[int] = []
var _food_view: EcsView
## Current food: id -> its diet.
var _diet: Dictionary = {}
var _bush_view: EcsView
## Current harvestables: id -> EcsHarvestableComponent.
var _bushes: Dictionary = {}

func label() -> StringName:
	return &"planning"

func run(world: EcsWorld, _delta: float) -> void:
	_refresh(world)
	var facts_of := {}
	var ranked_of := {}
	var planners := world.view([EcsPlannerComponent, EcsLowBrainComponent], [EcsDyingFlag])
	var columns := planners.column(EcsPlannerComponent)
	for k in planners.ids.size():
		var id := planners.ids[k]
		var planner := columns[k] as EcsPlannerComponent
		var facts := facts_for(world, id)
		var ranked := _rank(world, id, planner)
		facts_of[id] = facts
		ranked_of[id] = ranked
		if planner.dirty:
			continue
		if not planner.planned or facts != planner.facts or _ids(ranked) != planner.ranking:
			planner.dirty = true
			_queue.append(id)

	var done := 0
	while done < MAX_REPLANS and not _queue.is_empty():
		var id: int = _queue.pop_front()
		if not facts_of.has(id):
			continue
		_replan(world.get_component(id, EcsPlannerComponent) as EcsPlannerComponent,
			facts_of[id], ranked_of[id])
		done += 1

## How much `id` wants `goal` now: 0 above the need's gate, else `weight` times
## an urgency from FLOOR at the gate to 1 at empty.
static func score(world: EcsWorld, id: int, goal: EcsGoalDef) -> float:
	match goal.need:
		&"eat":
			var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent
			if hunger != null:
				return goal.weight * _urgency(hunger.fullness,
					minf(hunger.forage_below, hunger.eat_below))
		&"provision":
			var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent
			if hunger != null and world.has(id, EcsInventoryComponent):
				return goal.weight * _urgency(hunger.fullness, hunger.forage_below)
		&"rest":
			var energy := world.get_component(id, EcsEnergyComponent) as EcsEnergyComponent
			if energy != null:
				return goal.weight * _urgency(energy.value, energy.rest_at)
		&"flee":
			var danger := world.get_component(id, EcsDangerComponent) as EcsDangerComponent
			if danger != null and danger.value >= danger.flee_at:
				return goal.weight * (FLOOR + (1.0 - FLOOR)
					* (danger.value - danger.flee_at) / maxf(1.0 - danger.flee_at, 0.01))
	return 0.0

static func _urgency(value: float, gate: float) -> float:
	if value > gate:
		return 0.0
	return FLOOR + (1.0 - FLOOR) * (gate - value) / maxf(gate, 0.01)

## The goals that score above 0, best first, with the bonus on the current one.
func _rank(world: EcsWorld, id: int, planner: EcsPlannerComponent) -> Array[EcsGoalDef]:
	var scored: Array = []
	for goal in planner.goals:
		var value := score(world, id, goal)
		if value <= 0.0:
			continue
		if goal.id == planner.goal:
			value += COMMIT_BONUS
		scored.append([value, goal])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var ranked: Array[EcsGoalDef] = []
	for pair in scored:
		ranked.append(pair[1])
	return ranked

func _replan(planner: EcsPlannerComponent, facts: Dictionary,
		ranked: Array[EcsGoalDef]) -> void:
	planner.planned = true
	planner.dirty = false
	planner.replans += 1
	planner.facts = facts
	planner.ranking = _ids(ranked)
	planner.goal = &""
	planner.steps = []
	for goal in ranked:
		var steps := EcsPlanner.plan(facts, goal.desired, planner.actions)
		if not steps.is_empty():
			planner.goal = goal.id
			planner.steps = steps
			return

static func _ids(goals: Array[EcsGoalDef]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for goal in goals:
		ids.append(goal.id)
	return ids

## What is true for `id` now, as the planner's facts. Only true facts are kept,
## so two snapshots compare equal when nothing changed.
func facts_for(world: EcsWorld, id: int) -> Dictionary:
	var facts := {}
	var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent
	var bag := world.get_component(id, EcsInventoryComponent) as EcsInventoryComponent
	if hunger != null and hunger.fullness <= 0.0:
		facts[&"starving"] = true
	if bag != null:
		if bag.items.size() < bag.capacity:
			facts[&"has_room"] = true
		for record in bag.items:
			var food := record.component(EcsConsumableComponent) as EcsConsumableComponent
			if food != null and (hunger == null or food.diet == hunger.eats):
				facts[&"food_in_bag"] = true
				break
	var hunts := world.has(id, EcsDamageComponent)
	var danger := world.get_component(id, EcsDangerComponent) as EcsDangerComponent
	if danger != null and danger.value >= danger.flee_at:
		facts[&"threat_near"] = true
	else:
		facts[&"safe"] = true

	var action := world.get_component(id, EcsActionComponent) as EcsActionComponent
	if action != null:
		for touched in action.reached:
			if _edible(touched, hunger):
				facts[&"food_in_reach"] = true
				if world.has(touched, EcsPickableComponent):
					facts[&"item_in_reach"] = true
			if _harvestable(touched, hunger):
				facts[&"bush_in_reach"] = true
			if world.has(touched, EcsLootableComponent) and not world.has(touched, EcsDyingFlag):
				var held := world.get_component(touched, EcsInventoryComponent) as EcsInventoryComponent
				if held != null and not held.items.is_empty():
					facts[&"loot_in_reach"] = true
			if hunts and EcsHunting.can_hunt(world, id, touched):
				facts[&"prey_in_reach"] = true

	var sensor := world.get_component(id, EcsSensorComponent) as EcsSensorComponent
	if sensor != null:
		for seen in sensor.perceived:
			if _edible(seen, hunger):
				facts[&"food_in_sight"] = true
			elif _harvestable(seen, hunger):
				facts[&"bush_in_sight"] = true
			elif hunts and EcsHunting.can_hunt(world, id, seen):
				facts[&"prey_in_sight"] = true
	return facts

func _edible(id: int, hunger: EcsHungerComponent) -> bool:
	return _diet.has(id) and (hunger == null or _diet[id] == hunger.eats)

func _harvestable(id: int, hunger: EcsHungerComponent) -> bool:
	var crop: EcsHarvestableComponent = _bushes.get(id)
	return crop != null and crop.stock > 0 and (hunger == null or crop.diet == hunger.eats)

func _refresh(world: EcsWorld) -> void:
	var food := world.view([EcsConsumableComponent, EcsPositionComponent], [EcsDyingFlag])
	if food != _food_view:
		_food_view = food
		_diet = {}
		var foods := food.column(EcsConsumableComponent)
		for k in food.ids.size():
			_diet[food.ids[k]] = (foods[k] as EcsConsumableComponent).diet
	var plants := world.view([EcsHarvestableComponent, EcsPositionComponent], [EcsDyingFlag])
	if plants != _bush_view:
		_bush_view = plants
		_bushes = {}
		var crops := plants.column(EcsHarvestableComponent)
		for k in plants.ids.size():
			_bushes[plants.ids[k]] = crops[k]
