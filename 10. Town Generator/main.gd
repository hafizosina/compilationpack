extends Node2D

## Module 10 entry point: the town grid on module 9's ECS, with build tools.
## 1-4 terrain and 5-8 floor brushes, 0 clears floor, [ and ] size them. B drags a
## building's footprint; W and E drag a wood or stone wall line, X a removal line;
## C closes the building under the mouse. Middle-drag pans, the wheel zooms.
## Every tile layer is in the scene under World/TilemapGroup.

enum Tool { BRUSH, BUILDING, WALL, REMOVE }

@export var catalog: EcsTownCatalog
@export var entity_catalog: EcsEntityCatalog
## Grid size in cells.
@export var grid_size: Vector2i = Vector2i(96, 64)
## Terrain id every cell starts as.
@export var base_terrain: int = 1

@onready var _layers_root: Node = $World/TilemapGroup
@onready var _entities_root: Node2D = $World/Entities
@onready var _overlay: EcsTownOverlay = $World/Overlay
@onready var _camera: Camera2D = $Camera2D
@onready var _status: Label = $UI/Root/Status

var _world: EcsWorld
var _scheduler: EcsScheduler
var _build: EcsBuildCommandSystem
var _tile_sync: EcsTileSyncSystem
var _tool: Tool = Tool.BRUSH
## The brush's command and the terrain, floor or wall id it uses.
var _brush_kind: EcsBuildCommand.Kind = EcsBuildCommand.Kind.SET_TERRAIN
var _brush_id: int = 2
var _brush_size: int = 1
var _wall_type: int = 1
var _pressing: bool = false
var _press_cell: Vector2i = Vector2i.ZERO

func _ready() -> void:
	_world = EcsWorld.new()
	_world.add_singleton(EcsTownGrid.make(grid_size.x, grid_size.y, base_terrain))
	_world.add_singleton(EcsLifecycleSingleton.new())
	_build = EcsBuildCommandSystem.new(catalog)
	_tile_sync = EcsTileSyncSystem.new(_layers_root, catalog)
	_scheduler = EcsScheduler.new()
	_scheduler \
		.add(EcsLifecycleSystem.new(EcsEntityManager.new(_entities_root), entity_catalog)) \
		.add(_build) \
		.add(_tile_sync) \
		.add(EcsTownOverlaySystem.new(_overlay))
	_camera.position = Vector2(grid_size * EcsTownGrid.CELL) * 0.5

func _physics_process(delta: float) -> void:
	_scheduler.run_all(_world, delta)
	var refusal := "" if _build.refused == 0 else "   refused: %s" % _build.last_refusal
	_status.text = "%s   [1-4 terrain, 5-8 floor, 0 clear, [ ] size | B building, W/E wall, X remove, C close]   tile sync %d tiles, %d µs%s" % [
		_tool_name(), _tile_sync.redrawn, _tile_sync.last_usec, refusal]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := EcsTownGrid.cell_at(get_global_mouse_position())
		if event.pressed:
			_pressing = true
			_press_cell = cell
			if _tool == Tool.BRUSH:
				_paint(cell)
			else:
				_preview(cell)
		elif _pressing:
			_pressing = false
			if _tool != Tool.BRUSH:
				_finish(cell)
	elif event is InputEventMouseMotion and _pressing:
		var cell := EcsTownGrid.cell_at(get_global_mouse_position())
		if _tool == Tool.BRUSH:
			_paint(cell)
		else:
			_preview(cell)
	elif event is InputEventKey and event.pressed and not event.echo:
		_pick(event.keycode)

func _pick(key: Key) -> void:
	if key >= KEY_1 and key <= KEY_4:
		_tool = Tool.BRUSH
		_brush_kind = EcsBuildCommand.Kind.SET_TERRAIN
		_brush_id = key - KEY_0
	elif key >= KEY_5 and key <= KEY_8:
		_tool = Tool.BRUSH
		_brush_kind = EcsBuildCommand.Kind.SET_FLOOR
		_brush_id = key - KEY_4
	elif key == KEY_0:
		_tool = Tool.BRUSH
		_brush_kind = EcsBuildCommand.Kind.CLEAR_FLOOR
	elif key == KEY_B:
		_tool = Tool.BUILDING
	elif key == KEY_W or key == KEY_E:
		_tool = Tool.WALL
		_wall_type = 1 if key == KEY_W else 2
	elif key == KEY_X:
		_tool = Tool.REMOVE
	elif key == KEY_C:
		_close_building_under_mouse()
	elif key == KEY_BRACKETLEFT:
		_brush_size = maxi(_brush_size - 1, 1)
	elif key == KEY_BRACKETRIGHT:
		_brush_size = mini(_brush_size + 1, 8)

func _grid() -> EcsTownGridSingleton:
	return _world.get_singleton(EcsTownGridSingleton) as EcsTownGridSingleton

## Asks for the brush's cells around `centre`; the build system applies them next tick.
func _paint(centre: Vector2i) -> void:
	var half := _brush_size / 2
	for dy in _brush_size:
		for dx in _brush_size:
			_grid().commands.append(EcsBuildCommand.make(_brush_kind, centre + Vector2i(dx - half, dy - half), _brush_id))

## Shows what releasing at `cell` would do.
func _preview(cell: Vector2i) -> void:
	_overlay.preview_rect = _drag_rect(cell) if _tool == Tool.BUILDING else Rect2i()
	_overlay.preview.clear()
	if _tool != Tool.BUILDING:
		_overlay.preview.append_array(_drag_line(cell))
	_overlay.preview_bad = _tool == Tool.BUILDING and _overlaps(_drag_rect(cell))
	_overlay.queue_redraw()

## Sends the drag as commands.
func _finish(cell: Vector2i) -> void:
	match _tool:
		Tool.BUILDING:
			_grid().commands.append(EcsBuildCommand.create_building(_drag_rect(cell)))
		Tool.WALL:
			for at in _drag_line(cell):
				_grid().commands.append(EcsBuildCommand.make(EcsBuildCommand.Kind.PLACE_WALL, at, _wall_type))
		Tool.REMOVE:
			for at in _drag_line(cell):
				_grid().commands.append(EcsBuildCommand.make(EcsBuildCommand.Kind.REMOVE_STRUCTURE, at))
	_overlay.preview.clear()
	_overlay.preview_rect = Rect2i()
	_overlay.queue_redraw()

func _close_building_under_mouse() -> void:
	var cell := EcsTownGrid.cell_at(get_global_mouse_position())
	if not EcsTownGrid.in_bounds(_grid(), cell):
		return
	var command := EcsBuildCommand.new()
	command.kind = EcsBuildCommand.Kind.CLOSE_BUILDING
	command.building = _grid().building_id[EcsTownGrid.index(_grid(), cell)]
	_grid().commands.append(command)

## The rectangle from the press to `cell`, both corners included.
func _drag_rect(cell: Vector2i) -> Rect2i:
	var from := Vector2i(mini(_press_cell.x, cell.x), mini(_press_cell.y, cell.y))
	var to := Vector2i(maxi(_press_cell.x, cell.x), maxi(_press_cell.y, cell.y))
	return Rect2i(from, to - from + Vector2i.ONE)

## The straight line from the press towards `cell`, along whichever axis it moved more.
func _drag_line(cell: Vector2i) -> Array[Vector2i]:
	var delta := cell - _press_cell
	var step := Vector2i(signi(delta.x), 0) if absi(delta.x) >= absi(delta.y) else Vector2i(0, signi(delta.y))
	var length := maxi(absi(delta.x), absi(delta.y))
	var cells: Array[Vector2i] = []
	for i in length + 1:
		cells.append(_press_cell + step * i)
	return cells

## For the preview only; the build system decides.
func _overlaps(rect: Rect2i) -> bool:
	var grid := _grid()
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if EcsTownGrid.in_bounds(grid, Vector2i(x, y)) and grid.building_id[y * grid.width + x] != EcsTownGridSingleton.NO_ID:
				return true
	return false

func _tool_name() -> String:
	match _tool:
		Tool.BUILDING:
			return "building"
		Tool.WALL:
			return "wall: %s" % catalog.wall(_wall_type).display_name
		Tool.REMOVE:
			return "remove wall"
	match _brush_kind:
		EcsBuildCommand.Kind.SET_TERRAIN:
			return "terrain: %s  brush %d" % [catalog.terrain(_brush_id).display_name, _brush_size]
		EcsBuildCommand.Kind.SET_FLOOR:
			return "floor: %s  brush %d" % [catalog.floor_def(_brush_id).display_name, _brush_size]
	return "clear floor  brush %d" % _brush_size
