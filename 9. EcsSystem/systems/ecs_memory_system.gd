class_name EcsMemorySystem
extends EcsSystem

## Remembers what each animal sees that matters to it: water it drinks, food and bushes of
## its diet, lures it hides in, what can hunt it and what it can hunt. Facts fade while
## unseen, and one whose spot is in sight without its thing is forgotten at once. A pond
## where a threat was met is feared; a lure where prey or a kill was seen gains traffic.

var _water_view: EcsView
var _cover_view: EcsView
var _crop_view: EcsView
var _food_view: EcsView
var _hunter_view: EcsView
## Current drinkable water: id -> true.
var _water: Dictionary = {}
## Current lures, cover prey must visit: id -> its cover kind.
var _lures: Dictionary = {}
## Current harvestables: id -> EcsHarvestableComponent.
var _crops: Dictionary = {}
## Current food: id -> its diet.
var _food: Dictionary = {}
## Current meat-eaters that can attack: id -> true.
var _hunters: Dictionary = {}
## Diets some current food or harvestable yields: diet -> true.
var _diets: Dictionary = {}
var _ready_view: EcsView
## Current animals ready to breed: id -> their kind.
var _ready: Dictionary = {}
var _eater_view: EcsView
## Current eaters: id -> what they eat.
var _eats: Dictionary = {}

func label() -> StringName:
	return &"memory"

func run(world: EcsWorld, delta: float) -> void:
	_refresh(world)
	var minds := world.view([EcsMemoryComponent, EcsSensorComponent, EcsPositionComponent], [EcsDyingFlag])
	var memories := minds.column(EcsMemoryComponent)
	var sensors := minds.column(EcsSensorComponent)
	var places := minds.column(EcsPositionComponent)
	for k in minds.ids.size():
		var id := minds.ids[k]
		var memory := memories[k] as EcsMemoryComponent
		var sensor := sensors[k] as EcsSensorComponent
		var here := (places[k] as EcsPositionComponent).position
		var fade := delta / memory.remember_for
		var calm := delta / memory.fear_for
		var cool := pow(0.5, delta / memory.traffic_half_life)
		var sight := sensor.radius * sensor.radius
		var lures: Array[EcsMemoryFact] = []
		for about in memory.facts.keys():
			var fact := memory.facts[about] as EcsMemoryFact
			fact.strength -= fade
			if fact.strength <= 0.0 \
					or (here.distance_squared_to(fact.position) <= sight and not sensor.perceived.has(about)):
				memory.facts.erase(about)
				continue
			fact.fear = maxf(fact.fear - calm, 0.0)
			fact.traffic *= cool
			if fact.is_a(EcsMemoryFact.LURE):
				lures.append(fact)

		var danger := world.get_component(id, EcsDangerComponent) as EcsDangerComponent
		if danger != null and danger.value >= danger.flee_at:
			for about in memory.facts:
				var fact := memory.facts[about] as EcsMemoryFact
				if fact.is_a(EcsMemoryFact.WATER) and _near(fact, danger.threat_at, memory.near):
					fact.fear = 1.0

		var drinks := not _water.is_empty() and world.has(id, EcsThirstComponent)
		var eats: StringName = _eats.get(id, &"")
		if not _diets.has(eats):
			eats = &""
		var hunts := _hunters.has(id)
		var kinds: Array[StringName] = []
		if hunts and not _lures.is_empty():
			kinds = EcsHunting.kinds_in(world.get_component(id, EcsSkillsComponent) as EcsSkillsComponent)
		# Nothing it could learn by looking around: skip the walk.
		var kind := &""
		if not _ready.is_empty():
			kind = (world.get_component(id, EcsNameComponent) as EcsNameComponent).type_id
		if drinks or eats != &"" or hunts or kind != &"":
			_learn(world, id, here, sensor, memory, lures, drinks, eats, hunts, kinds, kind, delta)
		# A threat is the one danger already found, not another walk over what it sees.
		if danger != null and danger.threat != EcsWorld.NO_ENTITY and sensor.perceived.has(danger.threat) \
				and EcsHunting.notices(world, id, danger.threat, here):
			_write(world, memory, danger.threat, EcsMemoryFact.THREAT, true)

		if memory.facts.size() > memory.capacity:
			_forget_weakest(memory)

## Walks what `id` sees and remembers what matters to it.
func _learn(world: EcsWorld, id: int, here: Vector2, sensor: EcsSensorComponent,
		memory: EcsMemoryComponent, lures: Array[EcsMemoryFact], drinks: bool, eats: StringName,
		hunts: bool, kinds: Array[StringName], kind: StringName, delta: float) -> void:
	for seen in sensor.perceived:
		if not lures.is_empty():
			_count_traffic(world, id, here, seen, lures, memory, delta)
		var bits := 0
		if drinks and _water.has(seen):
			bits |= EcsMemoryFact.WATER
		if not kinds.is_empty() and _lures.has(seen) and kinds.has(_lures[seen]):
			bits |= EcsMemoryFact.LURE
		if eats != &"":
			if _food.get(seen, &"") == eats:
				bits |= EcsMemoryFact.FOOD
			var crop: EcsHarvestableComponent = _crops.get(seen)
			if crop != null and crop.diet == eats and crop.stock > 0:
				bits |= EcsMemoryFact.BUSH
		if hunts and _is_prey(world, id, seen, here):
			bits |= EcsMemoryFact.PREY
		if kind != &"" and seen != id and _ready.get(seen, &"") == kind:
			bits |= EcsMemoryFact.MATE
		# Threats are danger's to judge; the walk keeps the bit.
		var old := memory.facts.get(seen) as EcsMemoryFact
		if old != null:
			bits |= old.kinds & EcsMemoryFact.THREAT
		if bits == 0:
			# Seen as nothing that matters now, such as an emptied bush.
			memory.facts.erase(seen)
			continue
		_write(world, memory, seen, bits, false)

## EcsHunting.can_hunt and notices, for a known hunter: weaker, alive, and not hidden from it.
## Looked up per sighting, so no death rebuilds an index of every body.
func _is_prey(world: EcsWorld, id: int, seen: int, here: Vector2) -> bool:
	if seen == id or world.has(seen, EcsDyingFlag) or not world.has(seen, EcsPositionComponent):
		return false
	var theirs := world.get_component(seen, EcsHealthComponent) as EcsHealthComponent
	var mine := world.get_component(id, EcsHealthComponent) as EcsHealthComponent
	if theirs == null or mine == null or theirs.power >= mine.power:
		return false
	return not world.has(seen, EcsHiddenFlag) or EcsHunting.notices(world, id, seen, here)

## Remembers `seen` as `bits`, seen now: replacing its kinds, or adding to them.
func _write(world: EcsWorld, memory: EcsMemoryComponent, seen: int, bits: int, add: bool) -> void:
	# Seen by the sensor, gone since: nothing to remember.
	var at := world.get_component(seen, EcsPositionComponent) as EcsPositionComponent
	if at == null:
		memory.facts.erase(seen)
		return
	var fact := memory.facts.get(seen) as EcsMemoryFact
	if fact == null:
		fact = EcsMemoryFact.new()
		fact.about = seen
		memory.facts[seen] = fact
	fact.position = at.position
	var body := world.get_component(seen, EcsBodyComponent) as EcsBodyComponent
	fact.radius = body.radius if body != null else 0.0
	fact.kinds = (fact.kinds | bits) if add else bits
	fact.strength = 1.0

## Forgets the weakest facts until `memory` is at capacity, in one pass.
static func _forget_weakest(memory: EcsMemoryComponent) -> void:
	var facts := memory.facts.values()
	facts.sort_custom(func(a: EcsMemoryFact, b: EcsMemoryFact) -> bool: return a.strength < b.strength)
	for i in facts.size() - memory.capacity:
		memory.facts.erase((facts[i] as EcsMemoryFact).about)

## Prey `seen` near a lure adds `delta` to its traffic; a corpse near one adds
## `kill_traffic`, once.
func _count_traffic(world: EcsWorld, id: int, here: Vector2, seen: int, lures: Array[EcsMemoryFact],
		memory: EcsMemoryComponent, delta: float) -> void:
	var corpse := world.has(seen, EcsRotComponent)
	if not corpse and not (EcsHunting.can_hunt(world, id, seen) and EcsHunting.notices(world, id, seen, here)):
		return
	var at := world.get_component(seen, EcsPositionComponent) as EcsPositionComponent
	if at == null:
		return
	var there := at.position
	for fact in lures:
		if not _near(fact, there, memory.near):
			continue
		if not corpse:
			fact.traffic += delta
		elif not fact.kills_seen.has(seen):
			for old in fact.kills_seen.keys():
				if not world.is_alive(old):
					fact.kills_seen.erase(old)
			fact.kills_seen[seen] = true
			fact.traffic += memory.kill_traffic

static func _near(fact: EcsMemoryFact, point: Vector2, near: float) -> bool:
	var reach := fact.radius + near
	return fact.position.distance_squared_to(point) <= reach * reach

func _refresh(world: EcsWorld) -> void:
	var ready := world.view([EcsReadyFlag, EcsNameComponent], [EcsDyingFlag])
	if ready != _ready_view:
		_ready_view = ready
		_ready = {}
		var names := ready.column(EcsNameComponent)
		for k in ready.ids.size():
			_ready[ready.ids[k]] = (names[k] as EcsNameComponent).type_id
	var eaters := world.view([EcsHungerComponent])
	if eaters != _eater_view:
		_eater_view = eaters
		_eats = {}
		var hungers := eaters.column(EcsHungerComponent)
		for k in eaters.ids.size():
			_eats[eaters.ids[k]] = (hungers[k] as EcsHungerComponent).eats
	var food := world.view([EcsConsumableComponent, EcsPositionComponent], [EcsDyingFlag])
	var crops := world.view([EcsHarvestableComponent], [EcsDyingFlag])
	if food != _food_view or crops != _crop_view:
		_food_view = food
		_food = {}
		_diets = {}
		var foods := food.column(EcsConsumableComponent)
		for k in food.ids.size():
			_food[food.ids[k]] = (foods[k] as EcsConsumableComponent).diet
			_diets[_food[food.ids[k]]] = true
		for crop in crops.column(EcsHarvestableComponent):
			_diets[(crop as EcsHarvestableComponent).diet] = true
	var hunters := world.view([EcsDamageComponent, EcsHungerComponent], [EcsDyingFlag])
	if hunters != _hunter_view:
		_hunter_view = hunters
		_hunters = {}
		var hungers := hunters.column(EcsHungerComponent)
		for k in hunters.ids.size():
			if (hungers[k] as EcsHungerComponent).eats == &"meat":
				_hunters[hunters.ids[k]] = true
	var water := world.view([EcsDrinkableComponent], [EcsDyingFlag])
	var covers := world.view([EcsCoverComponent], [EcsDyingFlag])
	if water == _water_view and covers == _cover_view and crops == _crop_view:
		return
	_water_view = water
	_cover_view = covers
	_crop_view = crops
	_water = {}
	for id in water.ids:
		_water[id] = true
	_crops = {}
	var found_crops := crops.column(EcsHarvestableComponent)
	for k in crops.ids.size():
		_crops[crops.ids[k]] = found_crops[k]
	_lures = {}
	var found := covers.column(EcsCoverComponent)
	for k in covers.ids.size():
		var id := covers.ids[k]
		if _water.has(id) or _crops.has(id):
			_lures[id] = (found[k] as EcsCoverComponent).kind
