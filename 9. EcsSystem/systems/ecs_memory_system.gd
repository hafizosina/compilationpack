class_name EcsMemorySystem
extends EcsSystem

## Remembers the water and lures each animal sees. Facts fade while unseen, and one whose
## spot is in sight without its thing is forgotten at once.

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
		var sight := sensor.radius * sensor.radius
		for about in memory.facts.keys():
			var fact := memory.facts[about] as EcsMemoryFact
			fact.strength -= fade
			if fact.strength <= 0.0 \
					or (here.distance_squared_to(fact.position) <= sight and not sensor.perceived.has(about)):
				memory.facts.erase(about)

		var drinks := not _water.is_empty() and world.has(id, EcsThirstComponent)
		var kinds: Array[StringName] = []
		if not _lures.is_empty() and world.has(id, EcsDamageComponent):
			kinds = EcsHunting.kinds_in(world.get_component(id, EcsSkillsComponent) as EcsSkillsComponent)
		# Nothing it could learn: skip the walk.
		if drinks or not kinds.is_empty():
			for seen in sensor.perceived:
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
				fact.water = water
				fact.lure = lure
				fact.strength = 1.0

		while memory.facts.size() > memory.capacity:
			var weakest: int = memory.facts.keys()[0]
			for about in memory.facts:
				if (memory.facts[about] as EcsMemoryFact).strength < (memory.facts[weakest] as EcsMemoryFact).strength:
					weakest = about
			memory.facts.erase(weakest)

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
