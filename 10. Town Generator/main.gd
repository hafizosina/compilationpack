extends Node2D

## Module 10 entry point: the town grid on module 9's ECS, map input and the tools'
## commands; the HUD is the UI node's (EcsTownUI). Keys: Q turns a piece or a stamp, F5
## saves the town, F9 loads it; WASD or a middle-drag moves the camera, the wheel zooms.
## The tile layers are built from the catalog, under World/TilemapGroup, by EcsTileSyncSystem.

## What a tool does with the mouse.
const BRUSH_TOOLS: Array[StringName] = [&"terrain", &"floor"]
const DRAG_RECT_TOOLS: Array[StringName] = [&"building"]
const DRAG_LINE_TOOLS: Array[StringName] = [&"wall", &"remove"]
## Building defs shipped with the module, and those saved with the copy tool.
const BUILDING_DEFS := "res://10. Town Generator/defs/buildings/"
const SAVED_BUILDINGS := "user://buildings/"
const TOWN_FILE := EcsTownSave.SAVE_DIR + "town.tres"

@export var catalog: EcsTownCatalog
@export var entity_catalog: EcsEntityCatalog
## Grid size in cells.
@export var grid_size: Vector2i = Vector2i(96, 64)
## Terrain every cell starts as.
@export var base_terrain: StringName = &"grass"

@onready var _layers_root: Node = $World/TilemapGroup
@onready var _entities_root: Node2D = $World/Entities
@onready var _overlay: EcsTownOverlay = $World/Overlay
@onready var _camera: Camera2D = $Camera2D
@onready var _ui: EcsTownUI = $UI

var _world: EcsWorld
var _manager: EcsEntityManager
var _scheduler: EcsScheduler
var _build: EcsBuildCommandSystem
var _tile_sync: EcsTileSyncSystem
var _tool: StringName = &"terrain"
## The current tool's type: a terrain, floor (0 clears), wall or door id.
var _tool_id: int = 2
var _brush_size: int = 1
var _pressing: bool = false
var _press_cell: Vector2i = Vector2i.ZERO
## What the hover last showed, so the overlay redraws only on a change.
var _hover_key: Array = []
## Roofs start hidden.
var _show_roofs: bool = false
## Building defs the stamp tool offers; a choice's id is its index + 1.
var _stamps: Array[EcsBuildingDef] = []
## Quarter turns clockwise for the next stamp.
var _turns: int = 0

func _ready() -> void:
	catalog.number()
	_manager = EcsEntityManager.new(_entities_root)
	_start(EcsTownGrid.make(grid_size.x, grid_size.y, catalog.terrain_id(base_terrain)))
	_camera.position = Vector2(grid_size * EcsTownGrid.CELL) * 0.5
	_load_stamps()
	_ui.setup(catalog, entity_catalog, _stamps, _tool, _tool_id, _show_roofs, _overlay.show_rooms)
	_ui.tool_picked.connect(_on_tool_picked)
	_ui.brush_size_changed.connect(func(size: int) -> void: _brush_size = size)
	_ui.view_toggled.connect(_on_view_toggled)
	_ui.town_requested.connect(func(action: StringName) -> void: _save_town() if action == &"save" else _load_town())

## A new world on `grid`, its nodes cleared, with `commands` waiting for the first tick.
func _start(grid: EcsTownGridSingleton, commands: Array[EcsBuildCommand] = []) -> void:
	_manager.clear()
	_world = EcsWorld.new()
	_world.add_singleton(grid)
	_world.add_singleton(EcsLifecycleSingleton.new())
	grid.commands.append_array(commands)
	_build = EcsBuildCommandSystem.new(catalog, entity_catalog)
	_tile_sync = EcsTileSyncSystem.new(_layers_root, catalog)
	_tile_sync.roofs_visible = _show_roofs
	_scheduler = EcsScheduler.new()
	_scheduler \
		.add(EcsLifecycleSystem.new(_manager, entity_catalog)) \
		.add(_build) \
		.add(EcsRoomDetectionSystem.new(catalog)) \
		.add(EcsRoofSystem.new(catalog)) \
		.add(_tile_sync) \
		.add(EcsTownOverlaySystem.new(_overlay))
	_hover_key = []

func _physics_process(delta: float) -> void:
	_scheduler.run_all(_world, delta)
	_hover()
	var refusal := "" if _build.refused == 0 else "   refused: %s" % _build.last_refusal
	_ui.show_status(_tool, _tool_id, _brush_size, _turns,
		"%s   tile sync %d tiles, %d µs" % [refusal, _tile_sync.redrawn, _tile_sync.last_usec])

## Shows what the tool would do at the cell under the mouse, and whether the build system
## would refuse it — asked of EcsBuildRules, the build system's own checks.
func _hover() -> void:
	var cell := EcsTownGrid.cell_at(get_global_mouse_position())
	var over_panel := get_viewport().gui_get_hovered_control() != null
	var key := [] if over_panel or _pressing else [cell, _tool, _tool_id, _brush_size, _turns, _build.applied, _grid().pending.size()]
	if key == _hover_key:
		return
	_hover_key = key
	_overlay.clear_ghost()
	if not key.is_empty() and EcsTownGrid.in_bounds(_grid(), cell):
		_show_ghost(cell)

## The ghost at `cell`: the cells `_commands_at` would act on, the first command's verdict, and
## how the choice looks.
func _show_ghost(cell: Vector2i) -> void:
	var commands := _commands_at(cell)
	var look := _ui.ghost(_tool, _tool_id)
	var cells := Rect2i(cell, Vector2i.ONE)
	var reason := ""
	var marks: Array[Vector2i] = []
	var placed := _tool == &"furniture" or _tool == &"plant"
	match _tool:
		&"terrain", &"floor":
			cells = Rect2i(cell - Vector2i(_brush_size / 2, _brush_size / 2), Vector2i(_brush_size, _brush_size))
		&"furniture", &"plant":
			cells.size = EcsTownGrid.turned(look.get("size", Vector2i.ONE), _turns)
		&"copy":
			if _grid().building_id[EcsTownGrid.index(_grid(), cell)] <= EcsWorld.NO_ENTITY:
				reason = "no building"
		&"stamp":
			if commands.is_empty():
				return
			cells = commands[0].rect
			for command in commands:
				if command.kind == EcsBuildCommand.Kind.PLACE_WALL:
					marks.append(command.cell)
	if not commands.is_empty():
		reason = String(EcsBuildRules.refusal(_world, _grid(), catalog, entity_catalog, commands[0])).replace("_", " ")
	var texture: Texture2D = look.get("texture")
	if _tool == &"door" and EcsBuildRules.door_runs_down(_grid(), cell):
		texture = look["down"]
	_overlay.show_ghost(cells, texture, _turns if placed else 0, placed, reason, marks)

func _on_tool_picked(tool: StringName, id: int) -> void:
	_tool = tool
	_tool_id = id

func _on_view_toggled(view: StringName, on: bool) -> void:
	if view == &"roofs":
		_show_roofs = on
		_tile_sync.roofs_visible = on
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
	match key:
		KEY_Q:
			_turns = (_turns + 1) % 4
		KEY_F5:
			_save_town()
		KEY_F9:
			_load_town()

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
	_overlay.bad_cells.clear()
	if not rect:
		_overlay.preview.append_array(_drag_line(cell))
		if _tool == &"wall":
			for at in _overlay.preview:
				var command := EcsBuildCommand.make(EcsBuildCommand.Kind.PLACE_WALL, at, _tool_id)
				if EcsBuildRules.refusal(_world, _grid(), catalog, entity_catalog, command) != &"":
					_overlay.bad_cells.append(at)
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
				_grid().commands.append(EcsBuildCommand.make(_removal_at(at), at))
	_overlay.preview.clear()
	_overlay.bad_cells.clear()
	_overlay.preview_rect = Rect2i()
	_overlay.queue_redraw()

## Takes off what is on top of `cell`: its attachment, else its furniture, else its wall or door.
func _removal_at(cell: Vector2i) -> EcsBuildCommand.Kind:
	var grid := _grid()
	if not EcsTownGrid.in_bounds(grid, cell):
		return EcsBuildCommand.Kind.REMOVE_STRUCTURE
	var i := EcsTownGrid.index(grid, cell)
	if grid.attachment_id[i] != EcsTownGridSingleton.NO_ID:
		return EcsBuildCommand.Kind.DETACH
	if grid.object_id[i] != EcsTownGridSingleton.NO_ID and grid.structure[i] == EcsTownGridSingleton.NONE:
		return EcsBuildCommand.Kind.REMOVE_OBJECT
	return EcsBuildCommand.Kind.REMOVE_STRUCTURE

func _chosen_blueprint() -> StringName:
	return _ui.blueprint(_tool, _tool_id)

## A one-click tool on `cell`: sends what `_commands_at` gives, or saves the building there.
func _click(cell: Vector2i) -> void:
	if _tool == &"copy":
		if EcsTownGrid.in_bounds(_grid(), cell):
			_save_building(_grid().building_id[EcsTownGrid.index(_grid(), cell)])
		return
	_grid().commands.append_array(_commands_at(cell))

## The commands the tool in hand sends for a click at `cell` — a drag tool's one-cell version —
## and so what the hover checks: the one place a tool becomes commands. Empty for the brushes,
## remove and save building.
func _commands_at(cell: Vector2i) -> Array[EcsBuildCommand]:
	var commands: Array[EcsBuildCommand] = []
	match _tool:
		&"furniture", &"plant":
			commands.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, cell, _chosen_blueprint(), _turns))
		&"attach":
			commands.append(EcsBuildCommand.place(EcsBuildCommand.Kind.ATTACH, cell, _chosen_blueprint()))
		&"door":
			commands.append(EcsBuildCommand.make(EcsBuildCommand.Kind.PLACE_DOOR, cell, _tool_id))
		&"wall":
			commands.append(EcsBuildCommand.make(EcsBuildCommand.Kind.PLACE_WALL, cell, _tool_id))
		&"building":
			commands.append(EcsBuildCommand.create_building(Rect2i(cell, Vector2i.ONE)))
		&"toggle":
			commands.append(EcsBuildCommand.make(EcsBuildCommand.Kind.TOGGLE_DOOR, cell))
		&"close":
			if EcsTownGrid.in_bounds(_grid(), cell):
				var close := EcsBuildCommand.new()
				close.kind = EcsBuildCommand.Kind.CLOSE_BUILDING
				close.building = _grid().building_id[EcsTownGrid.index(_grid(), cell)]
				commands.append(close)
		&"stamp":
			if _chosen_stamp() != null:
				commands.append_array(EcsBuildingStamp.commands(_chosen_stamp(), catalog, entity_catalog, cell, _turns))
	return commands

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

func _chosen_stamp() -> EcsBuildingDef:
	return _stamps[_tool_id - 1] if _tool == &"stamp" and _tool_id >= 1 and _tool_id <= _stamps.size() else null

## The shipped building defs, then the ones saved with the copy tool.
func _load_stamps() -> void:
	for file in ResourceLoader.list_directory(BUILDING_DEFS):
		var def := load(BUILDING_DEFS + file) as EcsBuildingDef
		if def != null:
			_stamps.append(def)
	if not DirAccess.dir_exists_absolute(SAVED_BUILDINGS):
		return
	for file in DirAccess.get_files_at(SAVED_BUILDINGS):
		var def := ResourceLoader.load(SAVED_BUILDINGS + file, "", ResourceLoader.CACHE_MODE_IGNORE) as EcsBuildingDef
		if def != null:
			_stamps.append(def)

## Saves building `id` as a def under user://buildings/ and offers it as a stamp.
func _save_building(id: int) -> void:
	var n := _stamps.size() + 1
	while FileAccess.file_exists(SAVED_BUILDINGS + "building_%d.tres" % n):
		n += 1
	var key := StringName("building_%d" % n)
	var def := EcsBuildingStamp.capture(_world, _grid(), catalog, id, key)
	if def == null:
		return
	DirAccess.make_dir_recursive_absolute(SAVED_BUILDINGS)
	if ResourceSaver.save(def, SAVED_BUILDINGS + String(key) + ".tres") != OK:
		_ui.tell("could not save the building")
		return
	_stamps.append(def)
	_ui.set_stamps(_stamps, _stamps.size())
	_ui.tell("saved as %s" % def.display_name)

func _save_town() -> void:
	DirAccess.make_dir_recursive_absolute(EcsTownSave.SAVE_DIR)
	var saved := ResourceSaver.save(EcsTownSave.capture(_world, _grid(), catalog), TOWN_FILE)
	_ui.tell("town saved" if saved == OK else "could not save the town")

## Rebuilds the world from the saved town, by the same commands the tools send.
func _load_town() -> void:
	var save := ResourceLoader.load(TOWN_FILE, "", ResourceLoader.CACHE_MODE_IGNORE) as EcsTownSave
	if save == null:
		_ui.tell("no saved town")
		return
	var base := catalog.terrain_id(base_terrain)
	_start(EcsTownGrid.make(save.size.x, save.size.y, base), save.commands(catalog, entity_catalog, base))
	_ui.tell("town loaded")
