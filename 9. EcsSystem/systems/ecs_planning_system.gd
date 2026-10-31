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
const FLOOR: float = EcsNeeds.FLOOR
## Added to the current goal's score, so near-ties don't flicker.
const COMMIT_BONUS: float = 0.5
## Seconds of travel that cost one unit of a plan.
const TRAVEL_SECONDS: float = EcsMemoryFact.TRAVEL_SECONDS

## Memory kind -> [its known fact, its recall action, its in-sight action priced by place].
const RECALLS: Dictionary = {
	EcsMemoryFact.WATER: [&"water_known", &"recall_water", &"go_to_water"],
	EcsMemoryFact.LURE: [&"lure_known", &"recall_lure", &"go_to_lure"],
	EcsMemoryFact.FOOD: [&"food_known", &"recall_food", &""],
	EcsMemoryFact.BUSH: [&"bush_known", &"recall_bush", &""],
}

## Ids waiting for a replan, oldest first.
var _queue: Array[int] = []
var _food_view: EcsView
## Current food: id -> its diet.
var _diet: Dictionary = {}
var _bush_view: EcsView
## Current harvestables: id -> EcsHarvestableComponent.
var _bushes: Dictionary = {}
var _water_view: EcsView
## Current drinkable water: id -> true.
var _water: Dictionary = {}
var _cover_view: EcsView
## Current cover: id -> its kind.
var _covers: Dictionary = {}

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
		# Fetched once, shared by the facts and the scores.
		var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent
		var energy := world.get_component(id, EcsEnergyComponent) as EcsEnergyComponent
		var danger := world.get_component(id, EcsDangerComponent) as EcsDangerComponent
		var bag := world.get_component(id, EcsInventoryComponent) as EcsInventoryComponent
		var thirst := world.get_component(id, EcsThirstComponent) as EcsThirstComponent
		var facts := _facts(world, id, hunger, bag, danger, thirst)
		var ranked := _rank(planner, hunger, energy, danger, bag, thirst)
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
		_replan(world, id, world.get_component(id, EcsPlannerComponent) as EcsPlannerComponent,
			facts_of[id], ranked_of[id])
		done += 1

## The goals `id` scores above 0, best first. For tests and tools.
func rank(world: EcsWorld, id: int) -> Array[EcsGoalDef]:
	return _rank(world.get_component(id, EcsPlannerComponent) as EcsPlannerComponent,
		world.get_component(id, EcsHungerComponent) as EcsHungerComponent,
		world.get_component(id, EcsEnergyComponent) as EcsEnergyComponent,
		world.get_component(id, EcsDangerComponent) as EcsDangerComponent,
		world.get_component(id, EcsInventoryComponent) as EcsInventoryComponent,
		world.get_component(id, EcsThirstComponent) as EcsThirstComponent)

## How much `goal` is wanted: 0 above the need's gate, else `weight` times an
## urgency from FLOOR at the gate to 1 at empty. Any reading may be null.
static func score(goal: EcsGoalDef, hunger: EcsHungerComponent, energy: EcsEnergyComponent,
		danger: EcsDangerComponent, bag: EcsInventoryComponent,
		thirst: EcsThirstComponent = null) -> float:
	match goal.need:
		&"eat":
			return goal.weight * EcsNeeds.hunger_urgency(hunger)
		&"drink":
			return goal.weight * EcsNeeds.thirst_urgency(thirst)
		&"provision":
			if hunger != null and bag != null:
				return goal.weight * EcsNeeds.urgency(hunger.fullness, hunger.forage_below)
		&"rest":
			if energy != null:
				return goal.weight * EcsNeeds.urgency(energy.value, energy.rest_at)
		&"flee":
			if danger != null and danger.value >= danger.flee_at:
				return goal.weight * (FLOOR + (1.0 - FLOOR)
					* (danger.value - danger.flee_at) / maxf(1.0 - danger.flee_at, 0.01))
	return 0.0

## The goals that score above 0, best first, with the bonus on the current one.
static func _rank(planner: EcsPlannerComponent, hunger: EcsHungerComponent,
		energy: EcsEnergyComponent, danger: EcsDangerComponent,
		bag: EcsInventoryComponent, thirst: EcsThirstComponent) -> Array[EcsGoalDef]:
	var ranked: Array[EcsGoalDef] = []
	var values := PackedFloat32Array()
	for goal in planner.goals:
		var value := score(goal, hunger, energy, danger, bag, thirst)
		if value <= 0.0:
			continue
		if goal.id == planner.goal:
			value += COMMIT_BONUS
		# Insertion keeps it sorted; there are only a few goals.
		var at := 0
		while at < values.size() and values[at] >= value:
			at += 1
		values.insert(at, value)
		ranked.insert(at, goal)
	return ranked

func _replan(world: EcsWorld, id: int, planner: EcsPlannerComponent, facts: Dictionary,
		ranked: Array[EcsGoalDef]) -> void:
	planner.planned = true
	planner.dirty = false
	planner.replans += 1
	planner.facts = facts
	planner.ranking = _ids(ranked)
	planner.goal = &""
	planner.steps = []
	var costs := _costs(world, id, facts)
	for goal in ranked:
		var steps := EcsPlanner.plan(facts, goal.desired, planner.actions, costs)
		if not steps.is_empty():
			planner.goal = goal.id
			planner.steps = steps
			return

## Costs that come from this entity's stats, built only when it replans. A chase costs
## its expected time, and is impossible against prey at least as fast. Going to water or a
## lure costs the place it would go to: the walk, plus fear or the expected wait.
func _costs(world: EcsWorld, id: int, facts: Dictionary) -> Dictionary:
	var costs := {}
	var hunt := facts.has(&"prey_in_sight")
	var memory := world.get_component(id, EcsMemoryComponent) as EcsMemoryComponent
	var places := memory != null and (facts.has(&"water_known") or facts.has(&"lure_known") \
		or facts.has(&"food_known") or facts.has(&"bush_known"))
	if not hunt and not places:
		return costs
	var move := world.get_component(id, EcsMovementComponent) as EcsMovementComponent
	var here := (world.get_component(id, EcsPositionComponent) as EcsPositionComponent).position
	var sensor := world.get_component(id, EcsSensorComponent) as EcsSensorComponent
	if hunt:
		var best := INF
		for seen in sensor.perceived:
			if not EcsHunting.can_hunt(world, id, seen) or not EcsHunting.notices(world, id, seen, here):
				continue
			var theirs := world.get_component(seen, EcsMovementComponent) as EcsMovementComponent
			var closing := move.speed - (theirs.speed if theirs != null else 0.0)
			if closing <= 0.0:
				continue
			var there := (world.get_component(seen, EcsPositionComponent) as EcsPositionComponent).position
			best = minf(best, 1.0 + here.distance_to(there) / closing / TRAVEL_SECONDS)
		costs[&"hunt"] = best
	if places:
		for kind in RECALLS:
			var spec: Array = RECALLS[kind]
			if not facts.has(spec[0]):
				continue
			if spec[2] != &"":
				var near := EcsMemoryFact.best(memory, here, move.speed, kind, true, sensor.perceived)
				if near != null:
					costs[spec[2]] = EcsMemoryFact.score(near, memory, here, move.speed, kind)
			var known := EcsMemoryFact.best(memory, here, move.speed, kind)
			costs[spec[1]] = INF if known == null else EcsMemoryFact.score(known, memory, here, move.speed, kind)
	return costs

static func _ids(goals: Array[EcsGoalDef]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for goal in goals:
		ids.append(goal.id)
	return ids

## What is true for `id` now, as the planner's facts. Only true facts are kept,
## so two snapshots compare equal when nothing changed.
func _facts(world: EcsWorld, id: int, hunger: EcsHungerComponent, bag: EcsInventoryComponent,
		danger: EcsDangerComponent, thirst: EcsThirstComponent) -> Dictionary:
	var facts := {}
	if hunger != null and hunger.fullness <= 0.0:
		facts[&"starving"] = true
	if EcsNeeds.parched(thirst):
		facts[&"parched"] = true
	var drinks := thirst != null and not _water.is_empty()
	if bag != null:
		if bag.items.size() < bag.capacity:
			facts[&"has_room"] = true
		for record in bag.items:
			var food := record.component(EcsConsumableComponent) as EcsConsumableComponent
			if food != null and (hunger == null or food.diet == hunger.eats):
				facts[&"food_in_bag"] = true
				break
	var hunts := world.has(id, EcsDamageComponent)
	# One fetch for both; no cover in the world, no cover to look for.
	var known := world.get_component(id, EcsSkillsComponent) as EcsSkillsComponent
	var kinds: Array[StringName] = []
	if not _covers.is_empty():
		kinds = EcsHunting.kinds_in(known)
	if EcsHunting.dash_ready_in(known):
		facts[&"dash_ready"] = true
	var memory := world.get_component(id, EcsMemoryComponent) as EcsMemoryComponent
	if memory != null:
		for about in memory.facts:
			var fact := memory.facts[about] as EcsMemoryFact
			if fact.is_a(EcsMemoryFact.WATER) and drinks:
				facts[&"water_known"] = true
			if fact.is_a(EcsMemoryFact.LURE) and hunts:
				facts[&"lure_known"] = true
			if fact.is_a(EcsMemoryFact.FOOD):
				facts[&"food_known"] = true
			if fact.is_a(EcsMemoryFact.BUSH):
				facts[&"bush_known"] = true
	if danger != null and danger.value >= danger.flee_at:
		facts[&"threat_near"] = true
		# Only hiding reads it, and hiding needs a threat near.
		if _hunted(world, id, danger):
			facts[&"hunted"] = true
	else:
		facts[&"safe"] = true
	var here := Vector2.ZERO
	if hunts:
		here = (world.get_component(id, EcsPositionComponent) as EcsPositionComponent).position

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
			if hunts and EcsHunting.can_hunt(world, id, touched) \
					and EcsHunting.notices(world, id, touched, here):
				facts[&"prey_in_reach"] = true
			if drinks and _water.has(touched):
				facts[&"water_in_reach"] = true
			if _covers.has(touched) and kinds.has(_covers[touched]):
				facts[&"in_cover"] = true
				if hunts and _is_lure(touched):
					facts[&"prey_come_here"] = true

	var sensor := world.get_component(id, EcsSensorComponent) as EcsSensorComponent
	# Nothing to look for: skip the scan.
	if sensor != null and (hunts or drinks or not kinds.is_empty() or not _diet.is_empty() \
			or not _bushes.is_empty()):
		var dash_reach := EcsHunting.dash_reach(world, id) if hunts else 0.0
		for seen in sensor.perceived:
			if _covers.has(seen) and kinds.has(_covers[seen]):
				facts[&"cover_in_sight"] = true
				if hunts and _is_lure(seen):
					facts[&"lure_in_sight"] = true
			if _edible(seen, hunger):
				facts[&"food_in_sight"] = true
			elif _harvestable(seen, hunger):
				facts[&"bush_in_sight"] = true
			elif hunts and EcsHunting.can_hunt(world, id, seen) \
					and EcsHunting.notices(world, id, seen, here):
				facts[&"prey_in_sight"] = true
				if dash_reach > 0.0 and _within(world, seen, here, dash_reach):
					facts[&"prey_close"] = true
			elif drinks and _water.has(seen):
				facts[&"water_in_sight"] = true
	return facts

## Is the threat its danger found chasing or attacking it? Then it can't hide from it.
static func _hunted(world: EcsWorld, id: int, danger: EcsDangerComponent) -> bool:
	if not world.is_alive(danger.threat):
		return false
	var brain := world.get_component(danger.threat, EcsLowBrainComponent) as EcsLowBrainComponent
	return brain != null and brain.target == id and (brain.state == EcsLowBrainComponent.State.HUNT
		or brain.state == EcsLowBrainComponent.State.ATTACK or brain.state == EcsLowBrainComponent.State.POUNCE)

static func _within(world: EcsWorld, id: int, here: Vector2, distance: float) -> bool:
	var there := world.get_component(id, EcsPositionComponent) as EcsPositionComponent
	return there != null and here.distance_squared_to(there.position) <= distance * distance

## Drinkable or harvestable: somewhere prey must come.
func _is_lure(id: int) -> bool:
	return _water.has(id) or _bushes.has(id)

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
	var water := world.view([EcsDrinkableComponent], [EcsDyingFlag])
	if water != _water_view:
		_water_view = water
		_water = {}
		for id in water.ids:
			_water[id] = true
	var covers := world.view([EcsCoverComponent], [EcsDyingFlag])
	if covers != _cover_view:
		_cover_view = covers
		_covers = {}
		var found := covers.column(EcsCoverComponent)
		for k in covers.ids.size():
			_covers[covers.ids[k]] = (found[k] as EcsCoverComponent).kind
