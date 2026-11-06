class_name EcsMemorySystem
extends EcsSystem

## Remembers what each animal sees that matters to it: water it drinks, food and bushes of
## its diet, lures it hides in, what can hunt it and what it can hunt. Facts fade while
## unseen, and one whose spot is in sight without its thing is forgotten at once. A pond
## where a threat was met is feared; a lure where prey or a kill was seen gains traffic.

## The world index, as of this run.
var _index: EcsWorldIndexSingleton

func label() -> StringName:
	return &"memory"

func run(world: EcsWorld, delta: float) -> void:
	_index = EcsWorldIndex.of(world)
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

		var drinks := not _index.water.is_empty() and world.has(id, EcsThirstComponent)
		var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent
		var eats: StringName = hunger.eats if hunger != null else &""
		if not _index.diets.has(eats):
			eats = &""
		var hunts := _index.hunters.has(id)
		var kinds: Array[StringName] = []
		if hunts and not _index.lures.is_empty():
			kinds = EcsHunting.kinds_in(world.get_component(id, EcsSkillsComponent) as EcsSkillsComponent)
		# Nothing it could learn by looking around: skip the walk.
		var kind := &""
		if not _index.ready.is_empty():
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
		if hunts and _is_prey(world, id, seen, here):
			bits |= EcsMemoryFact.PREY
		if kind != &"" and seen != id and _index.ready.get(seen, &"") == kind:
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
