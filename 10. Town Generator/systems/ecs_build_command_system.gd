class_name EcsBuildCommandSystem
extends EcsSystem

## The only writer of grid cells. Validates and applies each pending build command,
## sets its result, and marks the cells whose look changed for the tile sync.
## A building is an entity born at the next lifecycle stage; until then its footprint
## is reserved under a token, so walls sent in the same batch already have an owner.
## Runs after lifecycle, so it binds the buildings born there first.

var _catalog: EcsTownCatalog
## Commands applied on the last run that had any, how many were refused, and why the last was.
var applied: int = 0
var refused: int = 0
var last_refusal: StringName = &""
var last_usec: int = 0

func _init(catalog: EcsTownCatalog) -> void:
	_catalog = catalog

func label() -> StringName:
	return &"build"

func run(world: EcsWorld, _delta: float) -> void:
	var grid := world.get_singleton(EcsTownGridSingleton) as EcsTownGridSingleton
	if grid == null:
		return
	if not grid.pending.is_empty():
		_bind_born(grid)
	if grid.commands.is_empty():
		return
	var started := Time.get_ticks_usec()
	applied = 0
	refused = 0
	for command in grid.commands:
		command.result = _apply(world, grid, command)
		if command.result == &"ok":
			applied += 1
		else:
			refused += 1
			last_refusal = command.result
	grid.commands.clear()
	last_usec = Time.get_ticks_usec() - started

func _apply(world: EcsWorld, grid: EcsTownGridSingleton, command: EcsBuildCommand) -> StringName:
	match command.kind:
		EcsBuildCommand.Kind.CREATE_BUILDING:
			return _create_building(world, grid, command)
		EcsBuildCommand.Kind.CLOSE_BUILDING:
			var building := world.get_component(command.building, EcsBuildingComponent) as EcsBuildingComponent \
				if command.building > EcsWorld.NO_ENTITY else null
			if building == null:
				return &"no_building"
			if not building.closed:
				building.closed = true
				grid.building_revision += 1
			return &"ok"
	if not EcsTownGrid.in_bounds(grid, command.cell):
		return &"out_of_bounds"
	var i := EcsTownGrid.index(grid, command.cell)
	match command.kind:
		EcsBuildCommand.Kind.SET_TERRAIN:
			if _catalog.terrain(command.value) == null:
				return &"unknown_terrain"
			if grid.terrain[i] != command.value:
				grid.terrain[i] = command.value
				_mark(grid, i, EcsTownGridSingleton.CHANGED_TERRAIN)
		EcsBuildCommand.Kind.SET_FLOOR:
			if _catalog.floor_def(command.value) == null:
				return &"unknown_floor"
			if grid.floor[i] != command.value:
				grid.floor[i] = command.value
				_mark(grid, i, EcsTownGridSingleton.CHANGED_FLOOR)
		EcsBuildCommand.Kind.CLEAR_FLOOR:
			if grid.floor[i] != 0:
				grid.floor[i] = 0
				_mark(grid, i, EcsTownGridSingleton.CHANGED_FLOOR)
		EcsBuildCommand.Kind.PLACE_WALL:
			if _catalog.wall(command.value) == null:
				return &"unknown_wall"
			if grid.building_id[i] == EcsTownGridSingleton.NO_ID:
				return &"outside_building"
			if command.building != EcsTownGridSingleton.NO_ID and command.building != grid.building_id[i]:
				return &"not_its_building"
			if grid.object_id[i] != EcsTownGridSingleton.NO_ID:
				return &"occupied"
			if grid.structure[i] != EcsTownGridSingleton.WALL or grid.wall_type[i] != command.value:
				grid.structure[i] = EcsTownGridSingleton.WALL
				grid.wall_type[i] = command.value
				_mark(grid, i, EcsTownGridSingleton.CHANGED_STRUCTURE)
		EcsBuildCommand.Kind.REMOVE_STRUCTURE:
			if grid.structure[i] != EcsTownGridSingleton.NONE:
				grid.structure[i] = EcsTownGridSingleton.NONE
				grid.wall_type[i] = 0
				_mark(grid, i, EcsTownGridSingleton.CHANGED_STRUCTURE)
	return &"ok"

## Reserves the footprint under a new token and asks lifecycle for the building.
## Footprints may touch but never overlap.
func _create_building(world: EcsWorld, grid: EcsTownGridSingleton, command: EcsBuildCommand) -> StringName:
	var rect := command.rect
	if not rect.has_area() or not Rect2i(0, 0, grid.width, grid.height).encloses(rect):
		return &"out_of_bounds"
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if grid.building_id[y * grid.width + x] != EcsTownGridSingleton.NO_ID:
				return &"overlaps"
	var inbox := world.get_singleton(EcsLifecycleSingleton) as EcsLifecycleSingleton
	if inbox == null:
		return &"no_lifecycle"
	var token := grid.next_token
	grid.next_token -= 1
	_fill(grid, rect, EcsTownGridSingleton.NO_ID, token)
	var note := EcsSpawnRequest.new()
	note.type_id = &"building"
	note.position = (Vector2(rect.position) + Vector2(rect.size) * 0.5) * EcsTownGrid.CELL
	note.overrides = {"building": {"footprint": rect}}
	inbox.spawn_requests.append(note)
	grid.pending[token] = note
	command.building = token
	return &"ok"

## Swaps each born building's token for its id; a failed spawn frees the footprint.
func _bind_born(grid: EcsTownGridSingleton) -> void:
	for token: int in grid.pending.keys():
		var note := grid.pending[token] as EcsSpawnRequest
		if not note.fulfilled:
			continue
		var rect: Rect2i = (note.overrides["building"] as Dictionary)["footprint"]
		_fill(grid, rect, token, note.born if note.born != EcsWorld.NO_ENTITY else EcsTownGridSingleton.NO_ID)
		grid.pending.erase(token)

## Sets `building_id` to `to` on every footprint cell holding `from`.
func _fill(grid: EcsTownGridSingleton, rect: Rect2i, from: int, to: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var i := y * grid.width + x
			if grid.building_id[i] == from:
				grid.building_id[i] = to

func _mark(grid: EcsTownGridSingleton, i: int, bits: int) -> void:
	grid.dirty[i] = int(grid.dirty.get(i, 0)) | bits
