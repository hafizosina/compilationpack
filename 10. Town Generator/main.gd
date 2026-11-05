extends Node2D

## Module 10 entry point: the town grid on module 9's ECS, with the build panel on the
## left. Shortcuts: 1-4 terrain, 5-8 floor, 0 clears floor, [ ] brush size; B building,
## C close one, W/E wood/stone wall, D/F wood/stone door, T open/close, X remove;
## S save a building as a def, P stamp one; Q turns a piece or a stamp;
## F5 save the town, F9 load it;
## R roofs, O room colours. Middle-drag pans, the wheel zooms.
## Every tile layer is in the scene under World/TilemapGroup.

## What a tool does with the mouse.
const BRUSH_TOOLS: Array[StringName] = [&"terrain", &"floor"]
const DRAG_RECT_TOOLS: Array[StringName] = [&"building"]
const DRAG_LINE_TOOLS: Array[StringName] = [&"wall", &"remove"]
const ICONS := "res://10. Town Generator/art/placeholder/icons/%s.png"
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
@onready var _status: Label = $UI/Root/StatusBar/Status
@onready var _panel: EcsBuildPanel = $UI/Root/BuildPanel

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
## Blueprints the furniture, plant and attach tools offer; a choice's id is its index + 1.
var _blueprints: Dictionary = {}
## What a tool's choice looks like as a ghost: tool -> {id -> {texture, size}}; doors also
## keep their upright tile under "down".
var _ghosts: Dictionary = {}
## What the hover last showed, so the overlay redraws only on a change.
var _hover_key: Array = []
## Building defs the stamp tool offers; a choice's id is its index + 1.
var _stamps: Array[EcsBuildingDef] = []
## Quarter turns clockwise for the next stamp.
var _turns: int = 0
## A short message for the status bar, and when it goes.
var _notice: String = ""
var _notice_until: int = 0

func _ready() -> void:
	catalog.number()
	_manager = EcsEntityManager.new(_entities_root)
	_start(EcsTownGrid.make(grid_size.x, grid_size.y, catalog.terrain_id(base_terrain)))
	_camera.position = Vector2(grid_size * EcsTownGrid.CELL) * 0.5
	_load_stamps()
	_panel.setup(_panel_tools())
	_panel.tool_picked.connect(_on_tool_picked)
	_panel.brush_size_changed.connect(func(size: int) -> void: _brush_size = size)
	_panel.view_toggled.connect(_on_view_toggled)
	_panel.town_requested.connect(func(action: StringName) -> void: _save_town() if action == &"save" else _load_town())
	_panel.select(_tool, _tool_id)
	_panel.set_views((_layers_root.get_node("RoofLayer") as TileMapLayer).visible, _overlay.show_rooms)

## A new world on `grid`, its nodes cleared, with `commands` waiting for the first tick.
func _start(grid: EcsTownGridSingleton, commands: Array[EcsBuildCommand] = []) -> void:
	_manager.clear()
	_world = EcsWorld.new()
	_world.add_singleton(grid)
	_world.add_singleton(EcsLifecycleSingleton.new())
	grid.commands.append_array(commands)
	_build = EcsBuildCommandSystem.new(catalog, entity_catalog)
	_tile_sync = EcsTileSyncSystem.new(_layers_root, catalog)
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
	var notice := "   " + _notice if Time.get_ticks_msec() < _notice_until else ""
	_status.text = "%s%s%s   tile sync %d tiles, %d µs" % [_tool_name(), refusal, notice, _tile_sync.redrawn, _tile_sync.last_usec]

func _tell(text: String) -> void:
	_notice = text
	_notice_until = Time.get_ticks_msec() + 4000

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
		var source := _wall_layer().tile_set.get_source(def.closed_source_id) as TileSetAtlasSource
		var across := _cut(source, def.closed_horizontal)
		doors.append({"id": def.id, "label": def.display_name.capitalize(), "icon": across})
		_ghost(&"door", def.id, across, Vector2i.ONE, _cut(source, def.closed_vertical))
	var furniture: Array = []
	var plants: Array = []
	var attachments: Array = []
	for def in entity_catalog.defs:
		var place := def.template(&"grid_position") as EcsGridPositionComponent
		var tile := def.template(&"tile") as EcsTileComponent
		if tile == null:
			continue
		var tool: StringName = &"furniture"
		var into := furniture
		if def.template(&"attachable") != null:
			tool = &"attach"
			into = attachments
		elif def.template(&"plant") != null:
			tool = &"plant"
			into = plants
		if not _blueprints.has(tool):
			_blueprints[tool] = []
		(_blueprints[tool] as Array).append(def.id)
		var layer := _layers_root.get_node(NodePath(catalog.attachment_layer if tool == &"attach" else catalog.furniture_layer)) as TileMapLayer
		var size := place.size if place != null else Vector2i.ONE
		var swatch := _cut_piece(layer.tile_set.get_source(tile.source_id) as TileSetAtlasSource, tile.atlas, size)
		into.append({"id": (_blueprints[tool] as Array).size(), "label": def.display_name, "icon": swatch})
		_ghost(tool, (_blueprints[tool] as Array).size(), swatch, size)
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
		{"tool": &"furniture", "label": "Furniture", "keys": "", "icon": load(ICONS % "furniture"),
			"hint": "Click to place it, top-left on the cell; Q turns it. Not on walls; a room takes its type from what's in it.",
			"choices": furniture},
		{"tool": &"plant", "label": "Plant", "keys": "", "icon": load(ICONS % "plant"),
			"hint": "Click to plant on bare ground, never on a floor; Q turns it.", "choices": plants},
		{"tool": &"attach", "label": "Attach", "keys": "", "icon": load(ICONS % "attach"),
			"hint": "Click a wall to hang it, or a table, stove or shelf to set it on.", "choices": attachments},
		{"tool": &"toggle", "label": "Open / close", "keys": "T", "icon": load(ICONS % "toggle"),
			"hint": "Click a door to open or close it."},
		{"tool": &"close", "label": "Close building", "keys": "C", "icon": load(ICONS % "close"),
			"hint": "Click a building to mark it finished."},
		{"tool": &"remove", "label": "Remove", "keys": "X", "icon": load(ICONS % "remove"),
			"hint": "Drag to take out what is on top of each cell: an attachment, then furniture, then a wall or door."},
		{"tool": &"copy", "label": "Save building", "keys": "S", "icon": load(ICONS % "copy"),
			"hint": "Click a building to save it as a def; it joins the stamps."},
		{"tool": &"stamp", "label": "Stamp", "keys": "P, Q", "icon": load(ICONS % "stamp"),
			"hint": "Click to build the chosen building, top-left on the cell. Q turns it a quarter.",
			"choices": _stamp_choices()},
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

## The tiles of a piece `size` cells big whose top-left tile is `coords`.
func _cut_piece(source: TileSetAtlasSource, coords: Vector2i, size: Vector2i) -> Texture2D:
	var swatch := AtlasTexture.new()
	swatch.atlas = source.texture
	var first := source.get_tile_texture_region(coords)
	swatch.region = Rect2i(first.position, first.size * size)
	return swatch

func _cut(source: TileSetAtlasSource, coords: Vector2i) -> Texture2D:
	var swatch := AtlasTexture.new()
	swatch.atlas = source.texture
	swatch.region = source.get_tile_texture_region(coords)
	return swatch

func _ghost(tool: StringName, id: int, texture: Texture2D, size: Vector2i, down: Texture2D = null) -> void:
	if not _ghosts.has(tool):
		_ghosts[tool] = {}
	_ghosts[tool][id] = {"texture": texture, "size": size, "down": down}

## Shows what the tool would do at the cell under the mouse, and whether the build system
## would refuse it — asked of EcsBuildRules, the build system's own checks.
func _hover() -> void:
	var cell := EcsTownGrid.cell_at(get_global_mouse_position())
	var over_panel := get_viewport().gui_get_hovered_control() != null
	var key := [] if over_panel or _pressing else [cell, _tool, _tool_id, _brush_size, _turns, _build.applied, _grid().pending.size()]
	if key == _hover_key:
		return
	_hover_key = key
	_overlay.ghost_cells = Rect2i()
	_overlay.ghost_texture = null
	_overlay.ghost_reason = ""
	_overlay.ghost_marks.clear()
	_overlay.ghost_turns = 0
	if not key.is_empty() and EcsTownGrid.in_bounds(_grid(), cell):
		_show_ghost(cell)
	_overlay.queue_redraw()

func _show_ghost(cell: Vector2i) -> void:
	var size := Vector2i.ONE
	var command: EcsBuildCommand = null
	var look: Dictionary = (_ghosts.get(_tool, {}) as Dictionary).get(_tool_id, {})
	match _tool:
		&"terrain", &"floor":
			size = Vector2i(_brush_size, _brush_size)
			cell -= Vector2i(_brush_size / 2, _brush_size / 2)
		&"furniture", &"plant":
			command = EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, cell, _chosen_blueprint(), _turns)
			size = EcsTownGrid.turned(look.get("size", Vector2i.ONE), _turns)
			_overlay.ghost_turns = _turns
		&"attach":
			command = EcsBuildCommand.place(EcsBuildCommand.Kind.ATTACH, cell, _chosen_blueprint())
		&"door":
			command = EcsBuildCommand.make(EcsBuildCommand.Kind.PLACE_DOOR, cell, _tool_id)
		&"wall":
			command = EcsBuildCommand.make(EcsBuildCommand.Kind.PLACE_WALL, cell, _tool_id)
		&"building":
			command = EcsBuildCommand.create_building(Rect2i(cell, Vector2i.ONE))
		&"toggle":
			command = EcsBuildCommand.make(EcsBuildCommand.Kind.TOGGLE_DOOR, cell)
		&"close":
			command = EcsBuildCommand.new()
			command.kind = EcsBuildCommand.Kind.CLOSE_BUILDING
			command.building = _grid().building_id[EcsTownGrid.index(_grid(), cell)]
		&"copy":
			if _grid().building_id[EcsTownGrid.index(_grid(), cell)] <= EcsWorld.NO_ENTITY:
				_overlay.ghost_reason = "no building"
		&"stamp":
			var def := _chosen_stamp()
			if def == null:
				return
			size = EcsBuildingStamp.turned_size(def, _turns)
			command = EcsBuildCommand.create_building(Rect2i(cell, size))
			for at: Vector2i in def.walls.keys() + def.doors.keys():
				_overlay.ghost_marks.append(cell + EcsTownGrid.turn(at, def.size, _turns))
	_overlay.ghost_cells = Rect2i(cell, size)
	if command != null:
		var why := EcsBuildRules.refusal(_world, _grid(), catalog, entity_catalog, command)
		_overlay.ghost_reason = String(why).replace("_", " ")
	var texture: Texture2D = look.get("texture")
	if texture == null:
		return
	var px := float(EcsTownGrid.CELL)
	if _tool == &"door" and EcsBuildRules.door_runs_down(_grid(), cell):
		texture = look["down"]
	_overlay.ghost_texture = texture
	var drawn := Vector2(texture.get_size())
	if _tool == &"furniture" or _tool == &"plant":
		drawn = Vector2(size) * px
	# Centred on the cell: an attachment's small icon, a door's oversized tile.
	_overlay.ghost_rect = Rect2(Vector2(cell) * px + (Vector2(size) * px - drawn) * 0.5, drawn)

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
	elif key == KEY_S:
		_use(&"copy")
	elif key == KEY_P:
		_use(&"stamp")
	elif key == KEY_Q:
		_turns = (_turns + 1) % 4
	elif key == KEY_F5:
		_save_town()
	elif key == KEY_F9:
		_load_town()
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
	var list: Array = _blueprints.get(_tool, [])
	return list[_tool_id - 1] if _tool_id >= 1 and _tool_id <= list.size() else &""

## A one-click tool on `cell`: place furniture, a plant, an attachment or a door; close a
## building; open or close a door.
func _click(cell: Vector2i) -> void:
	match _tool:
		&"furniture", &"plant":
			_grid().commands.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, cell, _chosen_blueprint(), _turns))
		&"attach":
			_grid().commands.append(EcsBuildCommand.place(EcsBuildCommand.Kind.ATTACH, cell, _chosen_blueprint()))
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
		&"copy":
			if EcsTownGrid.in_bounds(_grid(), cell):
				_save_building(_grid().building_id[EcsTownGrid.index(_grid(), cell)])
		&"stamp":
			if _chosen_stamp() != null:
				_grid().commands.append_array(EcsBuildingStamp.commands(_chosen_stamp(), catalog, entity_catalog, cell, _turns))

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
		&"furniture", &"plant":
			return "%s: %s, turned %d°" % [String(_tool).capitalize(), entity_catalog.get_def(_chosen_blueprint()).display_name, _turns * 90]
		&"attach":
			return "%s: %s" % [String(_tool).capitalize(), entity_catalog.get_def(_chosen_blueprint()).display_name]
		&"stamp":
			if _chosen_stamp() != null:
				return "Stamp: %s, turned %d°" % [_chosen_stamp().display_name, _turns * 90]
		&"copy":
			return "Save building"
	return String(_tool).capitalize()

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

func _stamp_choices() -> Array:
	var choices: Array = []
	for k in _stamps.size():
		choices.append({"id": k + 1, "label": _stamps[k].display_name, "icon": _plan_swatch(_stamps[k])})
	return choices

## A small plan of a def: floor, pieces, walls and doors, a few pixels a cell.
func _plan_swatch(def: EcsBuildingDef) -> Texture2D:
	const PX := 4
	var image := Image.create_empty(def.size.x * PX, def.size.y * PX, false, Image.FORMAT_RGBA8)
	var layers := [[def.floors, Color("#E7D6AC")], [def.objects, Color("#2F5E93")],
		[def.walls, Color("#5F3F22")], [def.doors, Color("#B98A32")]]
	for layer: Array in layers:
		for cell: Vector2i in layer[0]:
			image.fill_rect(Rect2i(cell * PX, Vector2i(PX, PX)), layer[1])
	return ImageTexture.create_from_image(image)

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
		_tell("could not save the building")
		return
	_stamps.append(def)
	_panel.set_choices(&"stamp", _stamp_choices(), _stamps.size())
	_tell("saved as %s" % def.display_name)

func _save_town() -> void:
	DirAccess.make_dir_recursive_absolute(EcsTownSave.SAVE_DIR)
	var saved := ResourceSaver.save(EcsTownSave.capture(_world, _grid(), catalog), TOWN_FILE)
	_tell("town saved" if saved == OK else "could not save the town")

## Rebuilds the world from the saved town, by the same commands the tools send.
func _load_town() -> void:
	var save := ResourceLoader.load(TOWN_FILE, "", ResourceLoader.CACHE_MODE_IGNORE) as EcsTownSave
	if save == null:
		_tell("no saved town")
		return
	var base := catalog.terrain_id(base_terrain)
	_start(EcsTownGrid.make(save.size.x, save.size.y, base), save.commands(catalog, entity_catalog, base))
	_tell("town loaded")
