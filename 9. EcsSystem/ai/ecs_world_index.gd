class_name EcsWorldIndex
extends RefCounted

## Keeps EcsWorldIndexSingleton current. A cache over views, refreshed when read as
## `EcsWorld.view()` is: each group is rebuilt only when its view changed. Readers call
## `of()` once per run. HANDOFF §31.

## `world`'s index, current as of now.
static func of(world: EcsWorld) -> EcsWorldIndexSingleton:
	var index := world.get_singleton(EcsWorldIndexSingleton) as EcsWorldIndexSingleton
	if index == null:
		index = world.add_singleton(EcsWorldIndexSingleton.new()) as EcsWorldIndexSingleton
	var food := world.view([EcsConsumableComponent, EcsPositionComponent], [EcsDyingFlag])
	var crops := world.view([EcsHarvestableComponent, EcsPositionComponent], [EcsDyingFlag])
	var water := world.view([EcsDrinkableComponent], [EcsDyingFlag])
	var covers := world.view([EcsCoverComponent], [EcsDyingFlag])
	var diets_stale := food != index.food_view or crops != index.crop_view
	var lures_stale := covers != index.cover_view or water != index.water_view \
		or crops != index.crop_view

	if food != index.food_view:
		index.food_view = food
		index.food = _table(food, EcsConsumableComponent)
		index.food_at = _table(food, EcsPositionComponent)
	if crops != index.crop_view:
		index.crop_view = crops
		index.crops = _table(crops, EcsHarvestableComponent)
		index.crop_at = _table(crops, EcsPositionComponent)
	if water != index.water_view:
		index.water_view = water
		index.water = _table(water, EcsDrinkableComponent)
	if covers != index.cover_view:
		index.cover_view = covers
		index.covers = _table(covers, EcsCoverComponent)
	if lures_stale:
		index.lures = {}
		for id: int in index.covers:
			if EcsHunting.is_lure(world, id):
				index.lures[id] = index.covers[id]
	if diets_stale:
		index.diets = {}
		for found: EcsConsumableComponent in index.food.values():
			index.diets[found.diet] = true
		for crop: EcsHarvestableComponent in index.crops.values():
			index.diets[crop.diet] = true

	var ready := world.view([EcsReadyFlag, EcsNameComponent], [EcsDyingFlag])
	if ready != index.ready_view:
		index.ready_view = ready
		index.ready = {}
		var names := ready.column(EcsNameComponent)
		for k in ready.ids.size():
			index.ready[ready.ids[k]] = (names[k] as EcsNameComponent).type_id
	var armed := world.view([EcsDamageComponent, EcsHungerComponent], [EcsDyingFlag])
	if armed != index.hunter_view:
		index.hunter_view = armed
		index.hunters = {}
		for id in armed.ids:
			if EcsHunting.is_hunter(world, id):
				index.hunters[id] = true
	return index

## id -> that id's `type` component, over `view`.
static func _table(view: EcsView, type: Script) -> Dictionary:
	var table := {}
	var column := view.column(type)
	for k in view.ids.size():
		table[view.ids[k]] = column[k]
	return table
