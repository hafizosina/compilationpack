class_name EcsPathSystem
extends EcsSystem

## Plans and follows paths on the town grid. Hands each selected walker the oldest order in
## EcsTownNavSingleton.orders, plans at most MAX_PLANS asked-for paths a run, replans a path
## when a cell still ahead of it has become solid, and gives movement the next cell whenever
## it stands with nowhere to go. Runs before movement, so a walker never waits a tick between cells.

const MAX_PLANS: int = 32

## Paths planned on the last run that planned any, how many found no way, and how long they took.
var planned: int = 0
var failed: int = 0
var last_usec: int = 0

func label() -> StringName:
	return &"path"

func run(world: EcsWorld, _delta: float) -> void:
	var nav := world.get_singleton(EcsTownNavSingleton) as EcsTownNavSingleton
	if nav == null or nav.astar.region.size == Vector2i.ZERO:
		return
	if not nav.orders.is_empty():
		_hand_out(world, nav)
	var view := world.view([EcsPositionComponent, EcsMovementComponent, EcsPathComponent])
	var places := view.column(EcsPositionComponent)
	var moves := view.column(EcsMovementComponent)
	var paths := view.column(EcsPathComponent)
	var budget := MAX_PLANS
	var started := Time.get_ticks_usec()
	var made := 0
	var none := 0
	for k in view.ids.size():
		var path := paths[k] as EcsPathComponent
		var move := moves[k] as EcsMovementComponent
		if path.revision != nav.revision and path.next < path.cells.size():
			path.revision = nav.revision
			if _blocked_ahead(nav, path):
				path.wants = true
		if path.wants and budget > 0:
			budget -= 1
			made += 1
			if not _plan(nav, path, move, (places[k] as EcsPositionComponent).position):
				none += 1
		if not move.has_destination and path.next < path.cells.size():
			_go(move, path.cells[path.next])
			path.next += 1
		elif not move.has_destination and not path.cells.is_empty():
			path.cells.clear()
			path.next = 0
	if made > 0:
		planned = made
		failed = none
		last_usec = Time.get_ticks_usec() - started

## Gives every selected walker the orders' last goal; earlier ones are overtaken.
func _hand_out(world: EcsWorld, nav: EcsTownNavSingleton) -> void:
	var goal: Vector2i = nav.orders.back()
	nav.orders.clear()
	for id in world.query([EcsPathComponent, EcsSelectedFlag]):
		var path := world.get_component(id, EcsPathComponent) as EcsPathComponent
		path.goal = goal
		path.wants = true

## Plans from where it stands to its goal and starts it on the first cell; false with no way.
func _plan(nav: EcsTownNavSingleton, path: EcsPathComponent, move: EcsMovementComponent, at: Vector2) -> bool:
	path.wants = false
	path.revision = nav.revision
	path.cells.clear()
	path.next = 0
	var from := EcsTownGrid.cell_at(at)
	var way: Array[Vector2i] = []
	if EcsTownNavSystem.walkable(nav, from) and EcsTownNavSystem.walkable(nav, path.goal):
		way = nav.astar.get_id_path(from, path.goal)
	path.failed = way.is_empty()
	if path.failed:
		return false
	way.remove_at(0)
	path.cells = way
	if path.cells.is_empty():
		return true
	_go(move, path.cells[0])
	path.next = 1
	return true

## True when a cell the walker has still to reach has become solid.
func _blocked_ahead(nav: EcsTownNavSingleton, path: EcsPathComponent) -> bool:
	for k in range(maxi(path.next - 1, 0), path.cells.size()):
		if nav.astar.is_point_solid(path.cells[k]):
			return true
	return false

## Sends movement to `cell`'s centre, as a new trip with its own time budget.
func _go(move: EcsMovementComponent, cell: Vector2i) -> void:
	move.destination = EcsTownGrid.centre_of(cell)
	move.has_destination = true
	move.time_left = 0.0
