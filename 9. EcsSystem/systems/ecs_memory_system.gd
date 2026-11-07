class_name EcsMemorySystem
extends EcsSystem

## Remembers what each animal sees that matters to it: water it drinks, food and bushes of
## its diet, lures it hides in, what can hunt it and what it can hunt. Nothing walks every
## fact each run: ages are timestamps read later, and only the fact it is walking to is checked
## against what it sees — its spot in sight without its thing, it is forgotten. A pond where a
## threat was met is feared; a lure where prey or a kill was seen gains traffic.

## Seconds between asking an animal's constant answers again.
const PROFILE_EVERY: float = 1.0
## Seconds between marking ponds feared while it flees.
const FEAR_EVERY: float = 1.0

## The world index, as of this run.
var _index: EcsWorldIndexSingleton
## This animal's lure facts, gathered the first time this run needs them.
var _lures: Array[EcsMemoryFact] = []
var _lures_ready: bool = false

func label() -> StringName:
	return &"memory"

func run(world: EcsWorld, delta: float) -> void:
	_index = EcsWorldIndex.of(world)
	var now := EcsClockSingleton.now_of(world)
	var minds := world.view([EcsMemoryComponent, EcsSensorComponent, EcsPositionComponent], [EcsDyingFlag])
	var memories := minds.column(EcsMemoryComponent)
	var sensors := minds.column(EcsSensorComponent)
	var places := minds.column(EcsPositionComponent)
	for k in minds.ids.size():
		var id := minds.ids[k]
		var memory := memories[k] as EcsMemoryComponent
		var sensor := sensors[k] as EcsSensorComponent
		var here := (places[k] as EcsPositionComponent).position
		memory.as_of = now
		_lures_ready = false

		var danger := world.get_component(id, EcsDangerComponent) as EcsDangerComponent
		memory.fear_left -= delta
		if danger == null or danger.value < danger.flee_at:
			memory.fear_left = 0.0
		elif memory.fear_left <= 0.0:
			memory.fear_left = FEAR_EVERY
			for about in memory.facts:
				var fact := memory.facts[about] as EcsMemoryFact
				if fact.is_a(EcsMemoryFact.WATER) and _near(fact, danger.threat_at, memory.near):
					fact.feared_at = now

		memory.profile_left -= delta
		if memory.profile_left <= 0.0:
			_profile(world, id, memory)
		var drinks := memory.drinks and not _index.water.is_empty()
		var eats := memory.eats if _index.diets.has(memory.eats) else &""
		var hunts := _index.hunters.has(id)
		var kinds: Array[StringName] = []
		if hunts and not _index.lures.is_empty():
			kinds = memory.hide_kinds
		# Nothing it could learn by looking around: skip the walk.
		var kind := memory.kind if not _index.ready.is_empty() else &""
		if drinks or eats != &"" or hunts or kind != &"":
			_learn(world, id, here, sensor, memory, drinks, eats, hunts, kinds, kind, delta)
		# A threat is the one danger already found, not another walk over what it sees.
		if danger != null and danger.threat != EcsWorld.NO_ENTITY and sensor.perceived.has(danger.threat) \
				and EcsHunting.notices(world, id, danger.threat, here):
			_write(world, memory, danger.threat, memory.facts.get(danger.threat) as EcsMemoryFact,
				EcsMemoryFact.THREAT, true)

		_check_watched(world.get_component(id, EcsMovementComponent) as EcsMovementComponent,
			memory, sensor, here)

		if memory.facts.size() > memory.capacity:
			_forget_weakest(memory)

## Checks the one fact at its latest destination, walking there or arrived: once that spot is
## in sight, the thing is there, or the fact is forgotten — for something that moves, only its
## place is. Matching a new destination to a fact
## walks the facts once per trip, never per run.
static func _check_watched(move: EcsMovementComponent, memory: EcsMemoryComponent,
		sensor: EcsSensorComponent, here: Vector2) -> void:
	if move != null and move.destination != memory.watch_spot:
		memory.watch_spot = move.destination
		memory.watching = EcsWorld.NO_ENTITY
		for about in memory.facts:
			if (memory.facts[about] as EcsMemoryFact).position == move.destination:
				memory.watching = about
				break
	if memory.watching == EcsWorld.NO_ENTITY:
		return
	var fact := memory.facts.get(memory.watching) as EcsMemoryFact
	if fact == null or fact.position != memory.watch_spot:
		memory.watching = EcsWorld.NO_ENTITY
		return
	if here.distance_squared_to(fact.position) > sensor.radius * sensor.radius \
			or sensor.perceived.has(fact.about):
		return
	if fact.fixed:
		memory.facts.erase(fact.about)
	else:
		fact.placed = false
	memory.watching = EcsWorld.NO_ENTITY

## Asks `id`'s constant answers again; each id keeps its own period so they don't all land on one run.
static func _profile(world: EcsWorld, id: int, memory: EcsMemoryComponent) -> void:
	memory.drinks = world.has(id, EcsThirstComponent)
	var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent
	memory.eats = hunger.eats if hunger != null else &""
	memory.hide_kinds = EcsHunting.kinds_in(world.get_component(id, EcsSkillsComponent) as EcsSkillsComponent)
	var name := world.get_component(id, EcsNameComponent) as EcsNameComponent
	memory.kind = name.type_id if name != null else &""
	memory.profile_left = PROFILE_EVERY * (0.5 + fposmod(id * 0.618034, 1.0))

## Walks what `id` sees and remembers what matters to it.
func _learn(world: EcsWorld, id: int, here: Vector2, sensor: EcsSensorComponent,
		memory: EcsMemoryComponent, drinks: bool, eats: StringName,
		hunts: bool, kinds: Array[StringName], kind: StringName, delta: float) -> void:
	for seen in sensor.perceived:
		var prey := hunts and _is_prey(world, id, seen, here)
		if not kinds.is_empty():
			_count_traffic(world, seen, prey, memory, delta)
		var bits := 0
		if drinks and _index.water.has(seen):
			bits |= EcsMemoryFact.WATER
		if not kinds.is_empty() and _index.lures.has(seen) and kinds.has((_index.lures[seen] as EcsCoverComponent).kind):
			bits |= EcsMemoryFact.LURE
		if eats != &"":
			if _index.food.has(seen) and (_index.food[seen] as EcsConsumableComponent).diet == eats:
				bits |= EcsMemoryFact.FOOD
			var crop: EcsHarvestableComponent = _index.crops.get(seen)
			if crop != null and crop.diet == eats and crop.stock > 0:
				bits |= EcsMemoryFact.BUSH
		if prey:
			bits |= EcsMemoryFact.PREY
		if kind != &"" and seen != id and _index.ready.get(seen, &"") == kind:
			bits |= EcsMemoryFact.MATE
		# Threats are danger's to judge; the walk keeps the bit.
		var old := memory.facts.get(seen) as EcsMemoryFact
		if old != null and old.kinds & EcsMemoryFact.THREAT != 0 \
				and EcsMemoryFact.strength_of(old, memory) > 0.0:
			bits |= EcsMemoryFact.THREAT
		if bits == 0:
			# Seen as nothing that matters now, such as an emptied bush.
			if old != null:
				memory.facts.erase(seen)
			continue
		_write(world, memory, seen, old, bits, false)

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

## Remembers `seen` as `bits`, seen now: replacing its kinds, or adding to them. `fact` is
## what it already knows of `seen`, or null.
func _write(world: EcsWorld, memory: EcsMemoryComponent, seen: int, fact: EcsMemoryFact, bits: int,
		add: bool) -> void:
	if fact == null or not fact.fixed:
		# Seen by the sensor, gone since: nothing to remember.
		var at := world.get_component(seen, EcsPositionComponent) as EcsPositionComponent
		if at == null:
			memory.facts.erase(seen)
			return
		var moves := world.get_component(seen, EcsMovementComponent) as EcsMovementComponent
		if fact == null:
			fact = EcsMemoryFact.new()
			fact.about = seen
			fact.fixed = moves == null
			var body := world.get_component(seen, EcsBodyComponent) as EcsBodyComponent
			fact.radius = body.radius if body != null else 0.0
			memory.facts[seen] = fact
		fact.position = at.position
		if moves != null:
			fact.velocity = moves.velocity
			fact.speed = moves.speed
		fact.placed = true
	fact.kinds = (fact.kinds | bits) if add else bits
	fact.seen_at = memory.as_of

## Forgets the weakest facts until `memory` is at capacity, in one pass.
static func _forget_weakest(memory: EcsMemoryComponent) -> void:
	var facts := memory.facts.values()
	facts.sort_custom(func(a: EcsMemoryFact, b: EcsMemoryFact) -> bool: return a.seen_at < b.seen_at)
	for i in facts.size() - memory.capacity:
		memory.facts.erase((facts[i] as EcsMemoryFact).about)

## Prey `seen` near a lure adds `delta` to its traffic; a corpse near one adds
## `kill_traffic`, once.
func _count_traffic(world: EcsWorld, seen: int, prey: bool, memory: EcsMemoryComponent,
		delta: float) -> void:
	var corpse := world.has(seen, EcsRotComponent)
	if not corpse and not prey:
		return
	var at := world.get_component(seen, EcsPositionComponent) as EcsPositionComponent
	if at == null:
		return
	if not _lures_ready:
		_lures_ready = true
		_lures.clear()
		for about in memory.facts:
			var lure := memory.facts[about] as EcsMemoryFact
			if lure.is_a(EcsMemoryFact.LURE) and EcsMemoryFact.strength_of(lure, memory) > 0.0:
				_lures.append(lure)
	var there := at.position
	for fact in _lures:
		if not _near(fact, there, memory.near):
			continue
		fact.traffic = EcsMemoryFact.traffic_of(fact, memory)
		fact.traffic_at = memory.as_of
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
