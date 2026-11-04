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
		_bind_born(world, grid)
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
		EcsBuildCommand.Kind.PLACE_DOOR:
			return _place_door(world, grid, command, i)
		EcsBuildCommand.Kind.TOGGLE_DOOR:
			if grid.structure[i] != EcsTownGridSingleton.DOOR:
				return &"not_a_door"
			var door := world.get_component(grid.object_id[i], EcsDoorComponent) as EcsDoorComponent \
				if grid.object_id[i] > EcsWorld.NO_ENTITY else null
			if door == null:
				return &"not_built_yet"
			door.is_open = not door.is_open
			_mark(grid, i, EcsTownGridSingleton.CHANGED_OBJECT)
		EcsBuildCommand.Kind.REMOVE_STRUCTURE:
			if grid.structure[i] == EcsTownGridSingleton.DOOR:
				_remove_object(world, grid, i)
			if grid.structure[i] != EcsTownGridSingleton.NONE:
				grid.structure[i] = EcsTownGridSingleton.NONE
				grid.wall_type[i] = 0
				_mark(grid, i, EcsTownGridSingleton.CHANGED_STRUCTURE)
	return &"ok"

## Turns a wall cell in a straight run of its building's walls into a door, and asks
## lifecycle for the door entity; the cell holds a token until it is born.
func _place_door(world: EcsWorld, grid: EcsTownGridSingleton, command: EcsBuildCommand, i: int) -> StringName:
	var def := _catalog.door(command.value)
	if def == null:
		return &"unknown_door"
	if grid.structure[i] != EcsTownGridSingleton.WALL:
		return &"not_on_wall"
	if command.building != EcsTownGridSingleton.NO_ID and command.building != grid.building_id[i]:
		return &"not_its_building"
	var across := _joins(grid, command.cell, Vector2i.LEFT) and _joins(grid, command.cell, Vector2i.RIGHT)
	var along := _joins(grid, command.cell, Vector2i.UP) and _joins(grid, command.cell, Vector2i.DOWN)
	if across == along:
		return &"not_a_straight_wall"
	var inbox := world.get_singleton(EcsLifecycleSingleton) as EcsLifecycleSingleton
	if inbox == null:
		return &"no_lifecycle"
	var token := grid.next_token
	grid.next_token -= 1
	grid.structure[i] = EcsTownGridSingleton.DOOR
	grid.wall_type[i] = def.id
	grid.object_id[i] = token
	var note := EcsSpawnRequest.new()
	note.type_id = def.blueprint
	note.position = EcsTownGrid.centre_of(command.cell)
	note.overrides = {"grid_position": {"cell": command.cell}}
	inbox.spawn_requests.append(note)
	grid.pending[token] = note
	_mark(grid, i, EcsTownGridSingleton.CHANGED_STRUCTURE)
	return &"ok"

## Whether the cell beside `cell` towards `side` is a wall or door of the same building.
func _joins(grid: EcsTownGridSingleton, cell: Vector2i, side: Vector2i) -> bool:
	var next := cell + side
	if not EcsTownGrid.in_bounds(grid, next):
		return false
	var n := EcsTownGrid.index(grid, next)
	return grid.structure[n] != EcsTownGridSingleton.NONE \
		and grid.building_id[n] == grid.building_id[EcsTownGrid.index(grid, cell)]

## Lets go of the object on cell `i`: a born one dies (cause removed) and leaves its
## building's children; an unborn one is killed when it binds.
func _remove_object(world: EcsWorld, grid: EcsTownGridSingleton, i: int) -> void:
	var id := grid.object_id[i]
	grid.object_id[i] = EcsTownGridSingleton.NO_ID
	if id <= EcsWorld.NO_ENTITY or not world.is_alive(id):
		return
	var dying := EcsDyingFlag.new()
	dying.cause = EcsDyingFlag.REMOVED
	world.add(id, dying)
	var building := world.get_component(grid.building_id[i], EcsBuildingComponent) as EcsBuildingComponent \
		if grid.building_id[i] > EcsWorld.NO_ENTITY else null
	if building != null:
		building.children.erase(id)

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

## Swaps each born entity's token for its id: on a building's footprint, or on an
## object's cell, adding the object to its building's children. A failed spawn frees the
## reservation; an object whose cell was cleared before it was born is removed at once.
func _bind_born(world: EcsWorld, grid: EcsTownGridSingleton) -> void:
	for token: int in grid.pending.keys():
		var note := grid.pending[token] as EcsSpawnRequest
		if not note.fulfilled:
			continue
		grid.pending.erase(token)
		var born := note.born if note.born != EcsWorld.NO_ENTITY else EcsTownGridSingleton.NO_ID
		if note.overrides.has("building"):
			_fill(grid, (note.overrides["building"] as Dictionary)["footprint"], token, born)
			continue
		var cell: Vector2i = (note.overrides["grid_position"] as Dictionary)["cell"]
		var i := EcsTownGrid.index(grid, cell)
		if grid.object_id[i] != token:
			if born != EcsTownGridSingleton.NO_ID:
				var dying := EcsDyingFlag.new()
				dying.cause = EcsDyingFlag.REMOVED
				world.add(born, dying)
			continue
		grid.object_id[i] = born
		var building := world.get_component(grid.building_id[i], EcsBuildingComponent) as EcsBuildingComponent \
			if grid.building_id[i] > EcsWorld.NO_ENTITY else null
		if building != null and born != EcsTownGridSingleton.NO_ID:
			building.children.append(born)
		_mark(grid, i, EcsTownGridSingleton.CHANGED_STRUCTURE)

## Sets `building_id` to `to` on every footprint cell holding `from`.
func _fill(grid: EcsTownGridSingleton, rect: Rect2i, from: int, to: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var i := y * grid.width + x
			if grid.building_id[i] == from:
				grid.building_id[i] = to

func _mark(grid: EcsTownGridSingleton, i: int, bits: int) -> void:
	grid.dirty[i] = int(grid.dirty.get(i, 0)) | bits
