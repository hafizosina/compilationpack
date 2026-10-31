class_name EcsMemorySystem
extends EcsSystem

## Remembers the water and lures each animal sees. Facts fade while unseen, and one whose
## spot is in sight without its thing is forgotten at once. A pond where a threat was met
## is feared; a lure where prey or a kill was seen gains traffic.

var _water_view: EcsView
var _cover_view: EcsView
var _crop_view: EcsView
## Current drinkable water: id -> true.
var _water: Dictionary = {}
## Current lures, cover prey must visit: id -> its cover kind.
var _lures: Dictionary = {}

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
			if fact.lure:
				lures.append(fact)

		var danger := world.get_component(id, EcsDangerComponent) as EcsDangerComponent
		if danger != null and danger.value >= danger.flee_at:
			for about in memory.facts:
				var fact := memory.facts[about] as EcsMemoryFact
				if fact.water and _near(fact, danger.threat_at, memory.near):
					fact.fear = 1.0

		var drinks := not _water.is_empty() and world.has(id, EcsThirstComponent)
		var kinds: Array[StringName] = []
		if not _lures.is_empty() and world.has(id, EcsDamageComponent):
			kinds = EcsHunting.kinds_in(world.get_component(id, EcsSkillsComponent) as EcsSkillsComponent)
		# Nothing it could learn: skip the walk.
		if drinks or not kinds.is_empty():
			for seen in sensor.perceived:
				if not lures.is_empty():
					_count_traffic(world, id, here, seen, lures, memory, delta)
				var water := drinks and _water.has(seen)
				var lure := not kinds.is_empty() and _lures.has(seen) and kinds.has(_lures[seen])
				if not water and not lure:
					continue
				var fact := memory.facts.get(seen) as EcsMemoryFact
				if fact == null:
					fact = EcsMemoryFact.new()
					fact.about = seen
					memory.facts[seen] = fact
				fact.position = (world.get_component(seen, EcsPositionComponent) as EcsPositionComponent).position
				var body := world.get_component(seen, EcsBodyComponent) as EcsBodyComponent
				fact.radius = body.radius if body != null else 0.0
				fact.water = water
				fact.lure = lure
				fact.strength = 1.0

		while memory.facts.size() > memory.capacity:
			var weakest: int = memory.facts.keys()[0]
			for about in memory.facts:
				if (memory.facts[about] as EcsMemoryFact).strength < (memory.facts[weakest] as EcsMemoryFact).strength:
					weakest = about
			memory.facts.erase(weakest)

## Prey `seen` near a lure adds `delta` to its traffic; a corpse near one adds
## `kill_traffic`, once.
func _count_traffic(world: EcsWorld, id: int, here: Vector2, seen: int, lures: Array[EcsMemoryFact],
		memory: EcsMemoryComponent, delta: float) -> void:
	var corpse := world.has(seen, EcsRotComponent)
	if not corpse and not (EcsHunting.can_hunt(world, id, seen) and EcsHunting.notices(world, id, seen, here)):
		return
	var there := (world.get_component(seen, EcsPositionComponent) as EcsPositionComponent).position
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
	var water := world.view([EcsDrinkableComponent], [EcsDyingFlag])
	var covers := world.view([EcsCoverComponent], [EcsDyingFlag])
	var crops := world.view([EcsHarvestableComponent], [EcsDyingFlag])
	if water == _water_view and covers == _cover_view and crops == _crop_view:
		return
	_water_view = water
	_cover_view = covers
	_crop_view = crops
	_water = {}
	for id in water.ids:
		_water[id] = true
	_lures = {}
	var found := covers.column(EcsCoverComponent)
	for k in covers.ids.size():
		var id := covers.ids[k]
		if _water.has(id) or crops.ids.has(id):
			_lures[id] = (found[k] as EcsCoverComponent).kind
