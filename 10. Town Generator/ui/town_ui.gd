class_name EcsTownUI
extends CanvasLayer

## Module 10's HUD: the build panel and the status bar. Builds the panel's tools from the
## catalogs, each type's swatch cut from its own sheet, and turns a panel choice back into
## what it means (a blueprint, a ghost). Never touches the world: main.gd hears its signals
## and tells it what to show.

signal tool_picked(tool: StringName, id: int)
signal brush_size_changed(size: int)
## &"roofs" or &"rooms".
signal view_toggled(view: StringName, on: bool)
## &"save" or &"load".
signal town_requested(action: StringName)

const ICONS := "res://10. Town Generator/art/placeholder/icons/%s.png"
## Doors share the wall tool's type list; a door's choice id is this plus its door id.
const DOOR_CHOICE: int = 100
## How long a notice stays on the status bar, in milliseconds.
const NOTICE_MS: int = 4000

@onready var _panel: EcsBuildPanel = $Root/BuildPanel
@onready var _status: Label = $Root/StatusBar/Status
@onready var _status_bar: Control = $Root/StatusBar

var _catalog: EcsTownCatalog
var _entities: EcsEntityCatalog
var _stamps: Array[EcsBuildingDef] = []
## Blueprints the furniture, plant and attach tools offer; a choice's id is its index + 1.
var _blueprints: Dictionary = {}
## What a choice looks like as a ghost: tool -> {id -> {texture, size, down}}; a door keeps
## its upright tile under "down".
var _ghosts: Dictionary = {}
var _notice: String = ""
var _notice_until: int = 0

func _ready() -> void:
	_panel.tool_picked.connect(_on_tool_picked)
	_panel.brush_size_changed.connect(func(size: int) -> void: brush_size_changed.emit(size))
	_panel.view_toggled.connect(func(view: StringName, on: bool) -> void: view_toggled.emit(view, on))
	_panel.town_requested.connect(func(action: StringName) -> void: town_requested.emit(action))
	# The HUD eats the mouse: a click, scroll or drag over it never reaches the map or camera.
	for surface: Control in [_panel, _status_bar]:
		surface.mouse_filter = Control.MOUSE_FILTER_STOP
		surface.gui_input.connect(_eat.bind(surface))

## A door picked among the wall tool's types is the door tool to everyone else.
func _on_tool_picked(tool: StringName, id: int) -> void:
	if tool == &"wall" and id >= DOOR_CHOICE:
		tool_picked.emit(&"door", id - DOOR_CHOICE)
	else:
		tool_picked.emit(tool, id)

func _eat(event: InputEvent, surface: Control) -> void:
	if event is InputEventMouse:
		surface.accept_event()

## Fills the panel from the catalogs and the stamps, and shows `tool` and its `id` picked.
func setup(catalog: EcsTownCatalog, entities: EcsEntityCatalog, stamps: Array[EcsBuildingDef],
		tool: StringName, id: int, roofs: bool, rooms: bool) -> void:
	_catalog = catalog
	_entities = entities
	_stamps = stamps
	_panel.setup(_tools())
	_panel.select(tool, id)
	_panel.set_views(roofs, rooms)

## Shows no tool picked, as a right-click on the map put it down.
func clear_tool() -> void:
	_panel.clear_tool()

## Offers `stamps` on the stamp tool, with stamp `id` chosen.
func set_stamps(stamps: Array[EcsBuildingDef], id: int) -> void:
	_stamps = stamps
	_panel.set_choices(&"stamp", _stamp_choices(), id)

## The blueprint behind choice `id` of the furniture, plant or attach tool, or &"".
func blueprint(tool: StringName, id: int) -> StringName:
	var list: Array = _blueprints.get(tool, [])
	return list[id - 1] if id >= 1 and id <= list.size() else &""

## How choice `id` of `tool` looks as a ghost: {texture, size, down}, or {} for none.
func ghost(tool: StringName, id: int) -> Dictionary:
	return (_ghosts.get(tool, {}) as Dictionary).get(id, {})

## Shows a short message on the status bar for a few seconds.
func tell(text: String) -> void:
	_notice = text
	_notice_until = Time.get_ticks_msec() + NOTICE_MS

## The status bar: what the tool in hand would do, then `extra` (refusals, costs).
func show_status(tool: StringName, id: int, brush: int, turns: int, extra: String) -> void:
	var notice := "   " + _notice if Time.get_ticks_msec() < _notice_until else ""
	_status.text = "%s%s%s" % [_tool_name(tool, id, brush, turns), notice, extra]

func _tool_name(tool: StringName, id: int, brush: int, turns: int) -> String:
	match tool:
		&"terrain":
			return "Terrain: %s, brush %d" % [_catalog.terrain(id).display_name, brush]
		&"floor":
			if id == 0:
				return "Floor: none, brush %d" % brush
			return "Floor: %s, brush %d" % [_catalog.floor_def(id).display_name, brush]
		&"wall":
			return "Wall: %s" % _catalog.wall(id).display_name
		&"door":
			return "Door: %s" % _catalog.door(id).display_name
		&"furniture", &"plant":
			return "%s: %s, turned %d°" % [String(tool).capitalize(), _entities.get_def(blueprint(tool, id)).display_name, turns * 90]
		&"attach":
			return "Attach: %s" % _entities.get_def(blueprint(tool, id)).display_name
		&"stamp":
			if id >= 1 and id <= _stamps.size():
				return "Stamp: %s, turned %d°" % [_stamps[id - 1].display_name, turns * 90]
		&"copy":
			return "Save building"
		&"":
			return "No tool"
	return String(tool).capitalize()

## The panel's tools, from the catalogs; each type's swatch is cut from its sheet.
func _tools() -> Array:
	var terrains: Array = []
	for def in _catalog.terrains:
		terrains.append({"id": def.id, "label": def.display_name.capitalize(), "icon": _dual_swatch(_catalog.tiles(def))})
	var floors: Array = []
	for def in _catalog.floors:
		floors.append({"id": def.id, "label": def.display_name.capitalize(), "icon": _dual_swatch(_catalog.tiles(def))})
	floors.append({"id": 0, "label": "None", "icon": load(ICONS % "none")})
	var walls: Array = []
	for def in _catalog.walls:
		walls.append({"id": def.id, "label": "%s wall" % def.display_name.capitalize(),
			"icon": _wall_swatch(def, EcsDualGrid.RIGHT | EcsDualGrid.BOTTOM | EcsDualGrid.LEFT | EcsDualGrid.TOP)})
	for def in _catalog.doors:
		var source := _catalog.wall_tiles().get_source(def.closed_source_id) as TileSetAtlasSource
		var across := _cut(source, def.closed_horizontal)
		walls.append({"id": DOOR_CHOICE + def.id, "label": "%s door" % def.display_name.capitalize(), "icon": across})
		_add_ghost(&"door", def.id, across, Vector2i.ONE, _cut(source, def.closed_vertical))
	var furniture: Array = []
	var plants: Array = []
	var attachments: Array = []
	for def in _entities.defs:
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
		var size := place.size if place != null else Vector2i.ONE
		var swatch := _cut_piece(tile, size)
		into.append({"id": (_blueprints[tool] as Array).size(), "label": def.display_name, "icon": swatch})
		_add_ghost(tool, (_blueprints[tool] as Array).size(), swatch, size)
	return [
		{"tool": &"terrain", "label": "Terrain", "icon": load(ICONS % "terrain"),
			"hint": "Drag to paint the ground.", "choices": terrains, "sized": true},
		{"tool": &"floor", "label": "Floor", "icon": load(ICONS % "floor"),
			"hint": "Drag to lay a floor. None takes it up.", "choices": floors, "sized": true},
		{"tool": &"building", "label": "Building", "icon": load(ICONS % "building"),
			"hint": "Drag a rectangle to claim a footprint. It turns red where it would overlap another."},
		{"tool": &"wall", "label": "Walls and doors", "icon": load(ICONS % "wall"),
			"hint": "A wall: drag a straight line inside a building. A door: click a straight wall to set it in.",
			"choices": walls},
		{"tool": &"furniture", "label": "Furniture", "icon": load(ICONS % "furniture"),
			"hint": "Click to place it, top-left on the cell; Q turns it. Not on walls; a room takes its type from what's in it.",
			"choices": furniture},
		{"tool": &"plant", "label": "Plant", "icon": load(ICONS % "plant"),
			"hint": "Click to plant on bare ground, never on a floor; Q turns it.", "choices": plants},
		{"tool": &"attach", "label": "Attach", "icon": load(ICONS % "attach"),
			"hint": "Click a wall to hang it, or a table, stove or shelf to set it on.", "choices": attachments},
		{"tool": &"toggle", "label": "Open / close", "icon": load(ICONS % "toggle"),
			"hint": "Click a door to open or close it."},
		{"tool": &"close", "label": "Close building", "icon": load(ICONS % "close"),
			"hint": "Click a building to mark it finished."},
		{"tool": &"remove", "label": "Remove", "icon": load(ICONS % "remove"),
			"hint": "Drag to take out what is on top of each cell: an attachment, then furniture, then a wall or door."},
		{"tool": &"copy", "label": "Save building", "icon": load(ICONS % "copy"),
			"hint": "Click a building to save it as a def; it joins the stamps."},
		{"tool": &"stamp", "label": "Stamp", "keys": "Q turns", "icon": load(ICONS % "stamp"),
			"hint": "Click to build the chosen building, top-left on the cell. Q turns it a quarter.",
			"choices": _stamp_choices()},
	]

func _stamp_choices() -> Array:
	var choices: Array = []
	for k in _stamps.size():
		choices.append({"id": k + 1, "label": _stamps[k].display_name, "icon": _plan_swatch(_stamps[k])})
	return choices

## A full tile of a dual-grid type's tiles, as it is drawn.
func _dual_swatch(tiles: TileSet) -> Texture2D:
	var source := tiles.get_source(tiles.get_source_id(0)) as TileSetAtlasSource
	return _cut(source, (EcsDualGrid.corner_layout(source)[EcsDualGrid.FULL] as Array)[0])

## A tile of wall `def` joined on `mask`'s sides.
func _wall_swatch(def: EcsWallDef, mask: int) -> Texture2D:
	var source := _catalog.wall_tiles().get_source(def.source_id) as TileSetAtlasSource
	return _cut(source, (EcsDualGrid.side_layout(source)[mask] as Array)[0])

## A piece `size` cells big, cut from its sheet from its top-left tile.
func _cut_piece(tile: EcsTileComponent, size: Vector2i) -> Texture2D:
	var swatch := AtlasTexture.new()
	swatch.atlas = tile.texture
	swatch.region = Rect2i(tile.atlas * tile.tile_size, size * tile.tile_size)
	return swatch

func _cut(source: TileSetAtlasSource, coords: Vector2i) -> Texture2D:
	var swatch := AtlasTexture.new()
	swatch.atlas = source.texture
	swatch.region = source.get_tile_texture_region(coords)
	return swatch

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

func _add_ghost(tool: StringName, id: int, texture: Texture2D, size: Vector2i, down: Texture2D = null) -> void:
	if not _ghosts.has(tool):
		_ghosts[tool] = {}
	_ghosts[tool][id] = {"texture": texture, "size": size, "down": down}
