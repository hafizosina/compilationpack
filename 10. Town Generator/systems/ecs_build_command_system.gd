class_name EcsBuildCommandSystem
extends EcsSystem

## The only writer of grid cells. Validates and applies each pending build command,
## sets its result, and marks the cells whose look changed for the tile sync.

var _catalog: EcsTownCatalog
## Commands applied on the last run, and the microseconds it took.
var applied: int = 0
var last_usec: int = 0

func _init(catalog: EcsTownCatalog) -> void:
	_catalog = catalog

func label() -> StringName:
	return &"build"

func run(world: EcsWorld, _delta: float) -> void:
	var grid := world.get_singleton(EcsTownGridSingleton) as EcsTownGridSingleton
	if grid == null or grid.commands.is_empty():
		return
	var started := Time.get_ticks_usec()
	applied = 0
	for command in grid.commands:
		command.result = _apply(grid, command)
		if command.result == &"ok":
			applied += 1
	grid.commands.clear()
	last_usec = Time.get_ticks_usec() - started

func _apply(grid: EcsTownGridSingleton, command: EcsBuildCommand) -> StringName:
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
			if grid.object_id[i] != -1:
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

func _mark(grid: EcsTownGridSingleton, i: int, bits: int) -> void:
	grid.dirty[i] = int(grid.dirty.get(i, 0)) | bits
