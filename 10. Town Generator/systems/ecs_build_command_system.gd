class_name EcsBuildCommandSystem
extends EcsSystem

## The only writer of grid cells. Validates and applies each pending build command,
## sets its result, and marks the cells whose look changed for the tile sync.
## Buildings, doors, furniture, plants and attachments are entities born at the next
## lifecycle stage; until then their cells hold a reservation token, so commands in the
## same batch can build on them. Runs after lifecycle, so it binds what was born there first.

var _catalog: EcsTownCatalog
var _entities: EcsEntityCatalog
## Commands applied on the last run that had any, how many were refused, and why the last was.
var applied: int = 0
var refused: int = 0
var last_refusal: StringName = &""
var last_usec: int = 0

func _init(catalog: EcsTownCatalog, entities: EcsEntityCatalog = null) -> void:
	_catalog = catalog
	_entities = entities

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
	var why := EcsBuildRules.refusal(world, grid, _catalog, _entities, command)
	if why != &"":
		return why
	match command.kind:
		EcsBuildCommand.Kind.CREATE_BUILDING:
			return _create_building(world, grid, command)
		EcsBuildCommand.Kind.CLOSE_BUILDING:
			var building := world.get_component(command.building, EcsBuildingComponent) as EcsBuildingComponent
			if not building.closed:
				building.closed = true
				grid.building_revision += 1
			return &"ok"
		EcsBuildCommand.Kind.PLACE_OBJECT:
			return _place_object(world, grid, command)
	var i := EcsTownGrid.index(grid, command.cell)
	match command.kind:
		EcsBuildCommand.Kind.SET_TERRAIN:
			if grid.terrain[i] != command.value:
				grid.terrain[i] = command.value
				_mark(grid, i, EcsTownGridSingleton.CHANGED_TERRAIN)
		EcsBuildCommand.Kind.SET_FLOOR:
			if grid.floor[i] != command.value:
				grid.floor[i] = command.value
				_mark(grid, i, EcsTownGridSingleton.CHANGED_FLOOR)
		EcsBuildCommand.Kind.CLEAR_FLOOR:
			if grid.floor[i] != 0:
				grid.floor[i] = 0
				_mark(grid, i, EcsTownGridSingleton.CHANGED_FLOOR)
		EcsBuildCommand.Kind.PLACE_WALL:
			if grid.structure[i] != EcsTownGridSingleton.WALL or grid.wall_type[i] != command.value:
				grid.structure[i] = EcsTownGridSingleton.WALL
				grid.wall_type[i] = command.value
				_mark(grid, i, EcsTownGridSingleton.CHANGED_STRUCTURE)
		EcsBuildCommand.Kind.PLACE_DOOR:
			return _place_door(world, grid, command, i)
		EcsBuildCommand.Kind.TOGGLE_DOOR:
			var door := world.get_component(grid.object_id[i], EcsDoorComponent) as EcsDoorComponent
			door.is_open = not door.is_open
			_mark(grid, i, EcsTownGridSingleton.CHANGED_OBJECT)
		EcsBuildCommand.Kind.REMOVE_STRUCTURE:
			_free_attachment(world, grid, i)
			if grid.structure[i] == EcsTownGridSingleton.DOOR:
				_free_object(world, grid, command.cell)
			if grid.structure[i] != EcsTownGridSingleton.NONE:
				grid.structure[i] = EcsTownGridSingleton.NONE
				grid.wall_type[i] = 0
				_mark(grid, i, EcsTownGridSingleton.CHANGED_STRUCTURE)
		EcsBuildCommand.Kind.REMOVE_OBJECT:
			_free_object(world, grid, command.cell)
		EcsBuildCommand.Kind.ATTACH:
			return _attach(world, grid, command, i)
		EcsBuildCommand.Kind.DETACH:
			_free_attachment(world, grid, i)
	return &"ok"

## Turns the wall cell into a door and asks lifecycle for the door entity.
func _place_door(world: EcsWorld, grid: EcsTownGridSingleton, command: EcsBuildCommand, i: int) -> StringName:
	var def := _catalog.door(command.value)
	var token := _reserve(world, grid, def.blueprint, EcsTownGrid.centre_of(command.cell),
		{"grid_position": {"cell": command.cell, "size": Vector2i.ONE}})
	if token == EcsTownGridSingleton.NO_ID:
		return &"no_lifecycle"
	_free_attachment(world, grid, i)
	grid.structure[i] = EcsTownGridSingleton.DOOR
	grid.wall_type[i] = def.id
	grid.object_id[i] = token
	_mark(grid, i, EcsTownGridSingleton.CHANGED_STRUCTURE)
	return &"ok"

## Reserves every cell the piece covers and asks lifecycle for it.
func _place_object(world: EcsWorld, grid: EcsTownGridSingleton, command: EcsBuildCommand) -> StringName:
	var place := EcsBuildRules.template(_entities, command.blueprint, &"grid_position") as EcsGridPositionComponent
	var rect := Rect2i(command.cell, place.size)
	var owner := grid.building_id[EcsTownGrid.index(grid, command.cell)]
	var token := _reserve(world, grid, command.blueprint, (Vector2(rect.position) + Vector2(rect.size) * 0.5) * EcsTownGrid.CELL,
		{"grid_position": {"cell": command.cell, "size": place.size}})
	if token == EcsTownGridSingleton.NO_ID:
		return &"no_lifecycle"
	for cell in EcsBuildRules.cells(rect):
		var i := EcsTownGrid.index(grid, cell)
		grid.object_id[i] = token
		_mark(grid, i, EcsTownGridSingleton.CHANGED_OBJECT)
	_queue_rooms(grid, owner)
	return &"ok"

## Reserves the slot and asks lifecycle for the attachment.
func _attach(world: EcsWorld, grid: EcsTownGridSingleton, command: EcsBuildCommand, i: int) -> StringName:
	var kind := EcsAttachedToComponent.HostKind.WALL_CELL if grid.structure[i] == EcsTownGridSingleton.WALL \
		else EcsAttachedToComponent.HostKind.ENTITY
	var token := _reserve(world, grid, command.blueprint, EcsTownGrid.centre_of(command.cell),
		{"attached_to": {"host_kind": kind, "host_cell": command.cell}})
	if token == EcsTownGridSingleton.NO_ID:
		return &"no_lifecycle"
	grid.attachment_id[i] = token
	_mark(grid, i, EcsTownGridSingleton.CHANGED_OBJECT)
	return &"ok"

## Asks lifecycle for `blueprint` and returns the reservation token, or NO_ID without lifecycle.
func _reserve(world: EcsWorld, grid: EcsTownGridSingleton, blueprint: StringName, at: Vector2,
		overrides: Dictionary) -> int:
	var inbox := world.get_singleton(EcsLifecycleSingleton) as EcsLifecycleSingleton
	if inbox == null:
		return EcsTownGridSingleton.NO_ID
	var token := grid.next_token
	grid.next_token -= 1
	var note := EcsSpawnRequest.new()
	note.type_id = blueprint
	note.position = at
	note.overrides = overrides
	inbox.spawn_requests.append(note)
	grid.pending[token] = note
	return token

## Lets go of the object covering `cell` — its attachments first: a born one dies (cause
## removed) and leaves its building's children; an unborn one is killed when it binds.
func _free_object(world: EcsWorld, grid: EcsTownGridSingleton, cell: Vector2i) -> void:
	var id := grid.object_id[EcsTownGrid.index(grid, cell)]
	var rect := Rect2i(cell, Vector2i.ONE)
	if id > EcsWorld.NO_ENTITY:
		var place := world.get_component(id, EcsGridPositionComponent) as EcsGridPositionComponent
		if place != null:
			rect = Rect2i(place.cell, place.size)
	elif grid.pending.has(id):
		var spot: Dictionary = (grid.pending[id] as EcsSpawnRequest).overrides["grid_position"]
		rect = Rect2i(spot["cell"], spot["size"])
	var owner := grid.building_id[EcsTownGrid.index(grid, rect.position)]
	for at in EcsBuildRules.cells(rect):
		var i := EcsTownGrid.index(grid, at)
		_free_attachment(world, grid, i)
		if grid.object_id[i] == id:
			grid.object_id[i] = EcsTownGridSingleton.NO_ID
			_mark(grid, i, EcsTownGridSingleton.CHANGED_OBJECT)
	_kill(world, grid, id, owner)
	_queue_rooms(grid, owner)

func _free_attachment(world: EcsWorld, grid: EcsTownGridSingleton, i: int) -> void:
	var id := grid.attachment_id[i]
	if id == EcsTownGridSingleton.NO_ID:
		return
	grid.attachment_id[i] = EcsTownGridSingleton.NO_ID
	_mark(grid, i, EcsTownGridSingleton.CHANGED_OBJECT)
	_kill(world, grid, id, grid.building_id[i])

## Removes a born entity (cause removed) from the world and its building's children.
func _kill(world: EcsWorld, grid: EcsTownGridSingleton, id: int, owner: int) -> void:
	if id <= EcsWorld.NO_ENTITY or not world.is_alive(id) or world.has(id, EcsDyingFlag):
		return
	var dying := EcsDyingFlag.new()
	dying.cause = EcsDyingFlag.REMOVED
	world.add(id, dying)
	var building := world.get_component(owner, EcsBuildingComponent) as EcsBuildingComponent \
		if owner > EcsWorld.NO_ENTITY else null
	if building != null:
		building.children.erase(id)

## Reserves the footprint under a new token and asks lifecycle for the building.
func _create_building(world: EcsWorld, grid: EcsTownGridSingleton, command: EcsBuildCommand) -> StringName:
	var rect := command.rect
	var token := _reserve(world, grid, &"building", (Vector2(rect.position) + Vector2(rect.size) * 0.5) * EcsTownGrid.CELL,
		{"building": {"footprint": rect}})
	if token == EcsTownGridSingleton.NO_ID:
		return &"no_lifecycle"
	_fill(grid, rect, EcsTownGridSingleton.NO_ID, token)
	command.building = token
	return &"ok"

## Swaps each born entity's token for its id: on a building's footprint, an object's cells or
## an attachment's slot, adding it to its building's children. A failed spawn frees the
## reservation; something whose cells were cleared before it was born is removed at once.
func _bind_born(world: EcsWorld, grid: EcsTownGridSingleton) -> void:
	for token: int in grid.pending.keys():
		var note := grid.pending[token] as EcsSpawnRequest
		if not note.fulfilled:
			continue
		grid.pending.erase(token)
		var born := note.born if note.born != EcsWorld.NO_ENTITY else EcsTownGridSingleton.NO_ID
		if note.overrides.has("building"):
			_fill(grid, (note.overrides["building"] as Dictionary)["footprint"], token, born)
			# Walls placed while it was a token had no building to queue.
			_queue_rooms(grid, born)
			continue
		var slot := note.overrides.has("attached_to")
		var spot: Dictionary = note.overrides["attached_to"] if slot else note.overrides["grid_position"]
		var cell: Vector2i = spot["host_cell"] if slot else spot["cell"]
		var i := EcsTownGrid.index(grid, cell)
		var held := grid.attachment_id[i] if slot else grid.object_id[i]
		if held != token:
			if born != EcsTownGridSingleton.NO_ID:
				_kill(world, grid, born, EcsTownGridSingleton.NO_ID)
			continue
		var covered: Array[Vector2i] = [cell]
		if not slot:
			covered = EcsBuildRules.cells(Rect2i(cell, spot["size"]))
		for at in covered:
			var k := EcsTownGrid.index(grid, at)
			if slot:
				grid.attachment_id[k] = born
			else:
				grid.object_id[k] = born
			_mark(grid, k, EcsTownGridSingleton.CHANGED_OBJECT)
		if born == EcsTownGridSingleton.NO_ID:
			continue
		if slot and int(spot["host_kind"]) == EcsAttachedToComponent.HostKind.ENTITY:
			var on := world.get_component(born, EcsAttachedToComponent) as EcsAttachedToComponent
			if on != null:
				on.host_id = grid.object_id[i]
		var building := world.get_component(grid.building_id[i], EcsBuildingComponent) as EcsBuildingComponent \
			if grid.building_id[i] > EcsWorld.NO_ENTITY else null
		if building != null:
			building.children.append(born)
		_queue_rooms(grid, grid.building_id[i])

## Sets `building_id` to `to` on every footprint cell holding `from`.
func _fill(grid: EcsTownGridSingleton, rect: Rect2i, from: int, to: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var i := y * grid.width + x
			if grid.building_id[i] == from:
				grid.building_id[i] = to

## Queues a building for room detection: its walls, doors or furniture changed.
func _queue_rooms(grid: EcsTownGridSingleton, building: int) -> void:
	if building > EcsWorld.NO_ENTITY:
		grid.dirty_buildings[building] = true

## Marks cell `i` for redraw; a wall or door change also queues its building for room detection.
func _mark(grid: EcsTownGridSingleton, i: int, bits: int) -> void:
	grid.dirty[i] = int(grid.dirty.get(i, 0)) | bits
	if bits & EcsTownGridSingleton.CHANGED_STRUCTURE:
		_queue_rooms(grid, grid.building_id[i])
