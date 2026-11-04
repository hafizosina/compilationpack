extends Node2D

## Module 10 entry point: the town grid on module 9's ECS, with the build panel on the
## left. Shortcuts: 1-4 terrain, 5-8 floor, 0 clears floor, [ ] brush size; B building,
## C close one, W/E wood/stone wall, D/F wood/stone door, T open/close, X remove;
## R roofs, O room colours. Middle-drag pans, the wheel zooms.
## Every tile layer is in the scene under World/TilemapGroup.

## What a tool does with the mouse.
const BRUSH_TOOLS: Array[StringName] = [&"terrain", &"floor"]
const DRAG_RECT_TOOLS: Array[StringName] = [&"building"]
const DRAG_LINE_TOOLS: Array[StringName] = [&"wall", &"remove"]
const ICONS := "res://10. Town Generator/art/placeholder/icons/%s.png"

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
@onready var _status: Label = $UI/Root/StatusBar/Status
@onready var _panel: EcsBuildPanel = $UI/Root/BuildPanel

var _world: EcsWorld
var _scheduler: EcsScheduler
var _build: EcsBuildCommandSystem
var _tile_sync: EcsTileSyncSystem
var _tool: StringName = &"terrain"
## The current tool's type: a terrain, floor (0 clears), wall or door id.
var _tool_id: int = 2
var _brush_size: int = 1
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
		.add(EcsRoomDetectionSystem.new()) \
		.add(EcsRoofSystem.new(catalog)) \
		.add(_tile_sync) \
		.add(EcsTownOverlaySystem.new(_overlay))
	_camera.position = Vector2(grid_size * EcsTownGrid.CELL) * 0.5
	_panel.setup(_panel_tools())
	_panel.tool_picked.connect(_on_tool_picked)
	_panel.brush_size_changed.connect(func(size: int) -> void: _brush_size = size)
	_panel.view_toggled.connect(_on_view_toggled)
	_panel.select(_tool, _tool_id)
	_panel.set_views((_layers_root.get_node("RoofLayer") as TileMapLayer).visible, _overlay.show_rooms)

func _physics_process(delta: float) -> void:
	_scheduler.run_all(_world, delta)
	var refusal := "" if _build.refused == 0 else "   refused: %s" % _build.last_refusal
	_status.text = "%s%s   tile sync %d tiles, %d µs" % [_tool_name(), refusal, _tile_sync.redrawn, _tile_sync.last_usec]

## The panel's tools, from the catalogs; each type's swatch is cut from the scene's own tiles.
func _panel_tools() -> Array:
	var terrains: Array = []
	for def in catalog.terrains:
		terrains.append({"id": def.id, "label": def.display_name.capitalize(), "icon": _dual_swatch(def.layer)})
	var floors: Array = []
	for def in catalog.floors:
		floors.append({"id": def.id, "label": def.display_name.capitalize(), "icon": _dual_swatch(def.layer)})
	floors.append({"id": 0, "label": "None", "icon": load(ICONS % "none")})
	var walls: Array = []
	for def in catalog.walls:
		walls.append({"id": def.id, "label": def.display_name.capitalize(),
			"icon": _wall_swatch(def.source_id, EcsDualGrid.RIGHT | EcsDualGrid.BOTTOM | EcsDualGrid.LEFT | EcsDualGrid.TOP)})
	var doors: Array = []
	for def in catalog.doors:
		doors.append({"id": def.id, "label": def.display_name.capitalize(),
			"icon": _cut(_wall_layer().tile_set.get_source(def.closed_source_id) as TileSetAtlasSource, def.closed_horizontal)})
	return [
		{"tool": &"terrain", "label": "Terrain", "keys": "1-4", "icon": load(ICONS % "terrain"),
			"hint": "Drag to paint the ground.", "choices": terrains, "sized": true},
		{"tool": &"floor", "label": "Floor", "keys": "5-8, 0", "icon": load(ICONS % "floor"),
			"hint": "Drag to lay a floor. None takes it up.", "choices": floors, "sized": true},
		{"tool": &"building", "label": "Building", "keys": "B", "icon": load(ICONS % "building"),
			"hint": "Drag a rectangle to claim a footprint. It turns red where it would overlap another."},
		{"tool": &"wall", "label": "Wall", "keys": "W, E", "icon": load(ICONS % "wall"),
			"hint": "Drag a straight line of wall inside a building.", "choices": walls},
		{"tool": &"door", "label": "Door", "keys": "D, F", "icon": load(ICONS % "door"),
			"hint": "Click a straight wall to set a door in it.", "choices": doors},
		{"tool": &"toggle", "label": "Open / close", "keys": "T", "icon": load(ICONS % "toggle"),
			"hint": "Click a door to open or close it."},
		{"tool": &"close", "label": "Close building", "keys": "C", "icon": load(ICONS % "close"),
			"hint": "Click a building to mark it finished."},
		{"tool": &"remove", "label": "Remove", "keys": "X", "icon": load(ICONS % "remove"),
			"hint": "Drag over walls and doors to take them out."},
	]

func _wall_layer() -> TileMapLayer:
	return _layers_root.get_node(NodePath(catalog.wall_layer)) as TileMapLayer

## A full tile of the dual-grid layer `layer_name`, as it is drawn.
func _dual_swatch(layer_name: StringName) -> Texture2D:
	var layer := _layers_root.get_node(NodePath(layer_name)) as TileMapLayer
	var source := layer.tile_set.get_source(layer.tile_set.get_source_id(0)) as TileSetAtlasSource
	return _cut(source, (EcsDualGrid.corner_layout(source)[EcsDualGrid.FULL] as Array)[0])

## A wall tile of `source_id` joined on `mask`'s sides.
func _wall_swatch(source_id: int, mask: int) -> Texture2D:
	var source := _wall_layer().tile_set.get_source(source_id) as TileSetAtlasSource
	return _cut(source, (EcsDualGrid.side_layout(source)[mask] as Array)[0])

func _cut(source: TileSetAtlasSource, coords: Vector2i) -> Texture2D:
	var swatch := AtlasTexture.new()
	swatch.atlas = source.texture
	swatch.region = source.get_tile_texture_region(coords)
	return swatch

func _on_tool_picked(tool: StringName, id: int) -> void:
	_tool = tool
	_tool_id = id

func _on_view_toggled(view: StringName, on: bool) -> void:
	if view == &"roofs":
		(_layers_root.get_node("RoofLayer") as TileMapLayer).visible = on
	else:
		_overlay.show_rooms = on
		_overlay.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := EcsTownGrid.cell_at(get_global_mouse_position())
		if event.pressed:
			_pressing = true
			_press_cell = cell
			if BRUSH_TOOLS.has(_tool):
				_paint(cell)
			elif DRAG_RECT_TOOLS.has(_tool) or DRAG_LINE_TOOLS.has(_tool):
				_preview(cell)
			else:
				_click(cell)
				_pressing = false
		elif _pressing:
			_pressing = false
			if not BRUSH_TOOLS.has(_tool):
				_finish(cell)
	elif event is InputEventMouseMotion and _pressing:
		var cell := EcsTownGrid.cell_at(get_global_mouse_position())
		if BRUSH_TOOLS.has(_tool):
			_paint(cell)
		else:
			_preview(cell)
	elif event is InputEventKey and event.pressed and not event.echo:
		_shortcut(event.keycode)

func _shortcut(key: Key) -> void:
	if key >= KEY_1 and key <= KEY_4:
		_use(&"terrain", key - KEY_0)
	elif key >= KEY_5 and key <= KEY_8:
		_use(&"floor", key - KEY_4)
	elif key == KEY_0:
		_use(&"floor", 0)
	elif key == KEY_B:
		_use(&"building")
	elif key == KEY_C:
		_use(&"close")
	elif key == KEY_W or key == KEY_E:
		_use(&"wall", 1 if key == KEY_W else 2)
	elif key == KEY_D or key == KEY_F:
		_use(&"door", 1 if key == KEY_D else 2)
	elif key == KEY_T:
		_use(&"toggle")
	elif key == KEY_X:
		_use(&"remove")
	elif key == KEY_R or key == KEY_O:
		var roofs := _layers_root.get_node("RoofLayer") as TileMapLayer
		if key == KEY_R:
			_on_view_toggled(&"roofs", not roofs.visible)
		else:
			_on_view_toggled(&"rooms", not _overlay.show_rooms)
		_panel.set_views(roofs.visible, _overlay.show_rooms)
	elif key == KEY_BRACKETLEFT or key == KEY_BRACKETRIGHT:
		_brush_size = clampi(_brush_size + (1 if key == KEY_BRACKETRIGHT else -1), 1, EcsBuildPanel.MAX_BRUSH)
		_panel.set_brush_size(_brush_size)

## Picks a tool from a shortcut and shows it on the panel.
func _use(tool: StringName, id: int = -1) -> void:
	_tool = tool
	if id >= 0:
		_tool_id = id
	_panel.select(tool, id)

func _grid() -> EcsTownGridSingleton:
	return _world.get_singleton(EcsTownGridSingleton) as EcsTownGridSingleton

## Asks for the brush's cells around `centre`; the build system applies them next tick.
func _paint(centre: Vector2i) -> void:
	var kind := EcsBuildCommand.Kind.SET_TERRAIN
	if _tool == &"floor":
		kind = EcsBuildCommand.Kind.SET_FLOOR if _tool_id != 0 else EcsBuildCommand.Kind.CLEAR_FLOOR
	var half := _brush_size / 2
	for dy in _brush_size:
		for dx in _brush_size:
			_grid().commands.append(EcsBuildCommand.make(kind, centre + Vector2i(dx - half, dy - half), _tool_id))

## Shows what releasing at `cell` would do.
func _preview(cell: Vector2i) -> void:
	var rect := DRAG_RECT_TOOLS.has(_tool)
	_overlay.preview_rect = _drag_rect(cell) if rect else Rect2i()
	_overlay.preview.clear()
	if not rect:
		_overlay.preview.append_array(_drag_line(cell))
	_overlay.preview_bad = rect and _overlaps(_drag_rect(cell))
	_overlay.queue_redraw()

## Sends the drag as commands.
func _finish(cell: Vector2i) -> void:
	match _tool:
		&"building":
			_grid().commands.append(EcsBuildCommand.create_building(_drag_rect(cell)))
		&"wall":
			for at in _drag_line(cell):
				_grid().commands.append(EcsBuildCommand.make(EcsBuildCommand.Kind.PLACE_WALL, at, _tool_id))
		&"remove":
			for at in _drag_line(cell):
				_grid().commands.append(EcsBuildCommand.make(EcsBuildCommand.Kind.REMOVE_STRUCTURE, at))
	_overlay.preview.clear()
	_overlay.preview_rect = Rect2i()
	_overlay.queue_redraw()

## A one-click tool on `cell`: close a building, place a door, open or close one.
func _click(cell: Vector2i) -> void:
	match _tool:
		&"door":
			_grid().commands.append(EcsBuildCommand.make(EcsBuildCommand.Kind.PLACE_DOOR, cell, _tool_id))
		&"toggle":
			_grid().commands.append(EcsBuildCommand.make(EcsBuildCommand.Kind.TOGGLE_DOOR, cell))
		&"close":
			if EcsTownGrid.in_bounds(_grid(), cell):
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
		&"terrain":
			return "Terrain: %s, brush %d" % [catalog.terrain(_tool_id).display_name, _brush_size]
		&"floor":
			if _tool_id == 0:
				return "Floor: none, brush %d" % _brush_size
			return "Floor: %s, brush %d" % [catalog.floor_def(_tool_id).display_name, _brush_size]
		&"wall":
			return "Wall: %s" % catalog.wall(_tool_id).display_name
		&"door":
			return "Door: %s" % catalog.door(_tool_id).display_name
	return String(_tool).capitalize()
