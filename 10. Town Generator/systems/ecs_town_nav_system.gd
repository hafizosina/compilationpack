class_name EcsTownNavSystem
extends EcsSystem

## The only writer of EcsTownNavSingleton.astar. Builds it from the whole grid on its first run,
## then updates only the cells the build system marked dirty. Must run before the tile sync,
## which clears `dirty`.

const CHANGES: int = EcsTownGridSingleton.CHANGED_TERRAIN | EcsTownGridSingleton.CHANGED_FLOOR \
	| EcsTownGridSingleton.CHANGED_STRUCTURE | EcsTownGridSingleton.CHANGED_OBJECT

var _catalog: EcsTownCatalog
var _built: bool = false
## Cells updated on the last run that changed any, and how long that run took.
var updated: int = 0
var last_usec: int = 0

func _init(catalog: EcsTownCatalog) -> void:
	_catalog = catalog

func label() -> StringName:
	return &"nav"

func run(world: EcsWorld, _delta: float) -> void:
	var grid := world.get_singleton(EcsTownGridSingleton) as EcsTownGridSingleton
	var nav := world.get_singleton(EcsTownNavSingleton) as EcsTownNavSingleton
	if grid == null or nav == null:
		return
	if not _built:
		_build(world, grid, nav)
		_built = true
		return
	if grid.dirty.is_empty():
		return
	var started := Time.get_ticks_usec()
	var changed := 0
	for i: int in grid.dirty:
		if int(grid.dirty[i]) & CHANGES and _update(world, grid, nav, i):
			changed += 1
	if changed > 0:
		nav.revision += 1
		updated = changed
		last_usec = Time.get_ticks_usec() - started

## True when `cell` is on the grid and can be stood on.
static func walkable(nav: EcsTownNavSingleton, cell: Vector2i) -> bool:
	return nav.astar.is_in_boundsv(cell) and not nav.astar.is_point_solid(cell)

## What a step onto cell `i` costs; 0 can't be walked. A wall, furniture, a plant or rubble
## blocks, but for walkable furniture (a gate) once born; a door is walked through unless locked;
## a floor's cost replaces its terrain's.
func cost(world: EcsWorld, grid: EcsTownGridSingleton, i: int) -> float:
	match grid.structure[i]:
		EcsTownGridSingleton.WALL:
			return 0.0
		EcsTownGridSingleton.DOOR:
			var door := world.get_component(grid.object_id[i], EcsDoorComponent) as EcsDoorComponent \
				if grid.object_id[i] > EcsWorld.NO_ENTITY else null
			return 0.0 if door != null and door.is_locked else 1.0
	if grid.object_id[i] != EcsTownGridSingleton.NO_ID:
		var piece := world.get_component(grid.object_id[i], EcsFurnitureComponent) as EcsFurnitureComponent \
			if grid.object_id[i] > EcsWorld.NO_ENTITY else null
		if piece == null or not piece.walkable:
			return 0.0
	if grid.floor[i] != 0:
		return _catalog.floor_def(grid.floor[i]).walk_cost
	return _catalog.terrain(grid.terrain[i]).walk_cost

func _build(world: EcsWorld, grid: EcsTownGridSingleton, nav: EcsTownNavSingleton) -> void:
	var started := Time.get_ticks_usec()
	nav.astar.region = Rect2i(0, 0, grid.width, grid.height)
	nav.astar.cell_size = Vector2(EcsTownGrid.CELL, EcsTownGrid.CELL)
	nav.astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	nav.astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	nav.astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	nav.astar.update()
	for i in grid.width * grid.height:
		_update(world, grid, nav, i)
	nav.revision += 1
	updated = grid.width * grid.height
	last_usec = Time.get_ticks_usec() - started

## Writes cell `i`'s solidity and cost; true when either changed.
func _update(world: EcsWorld, grid: EcsTownGridSingleton, nav: EcsTownNavSingleton, i: int) -> bool:
	var cell := Vector2i(i % grid.width, i / grid.width)
	var step := cost(world, grid, i)
	var solid := step <= 0.0
	var was_solid := nav.astar.is_point_solid(cell)
	if solid:
		nav.astar.set_point_solid(cell, true)
		return not was_solid
	var was_cost := nav.astar.get_point_weight_scale(cell)
	if was_solid:
		nav.astar.set_point_solid(cell, false)
	if was_cost != step:
		nav.astar.set_point_weight_scale(cell, step)
	return was_solid or was_cost != step
