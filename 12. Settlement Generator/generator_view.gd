extends Node2D

## The terrain generator's viewer: an L2 region and, zoomed in, its L1 ground in chunks. A bar and
## a line under Generate say what is being made and how far along it is.
## Generate plans the region (8 m a cell). The wheel zooms toward the mouse; past a zoom where L1
## cells are big enough to see (1 m a cell, drawn at 1/8 over the region), the chunks in view and a
## ring round them are made, each in turn: terrain planned, terrain drawn, objects planned, objects
## drawn (EcsTerrainChunks says which). Planning and building a chunk's world run on worker
## threads, off the scene tree: drawing objects rebuilds the chunk with them and swaps it in over
## the terrain-only one, so the main thread only ever adds a finished chunk. Made chunks stay in
## memory; far ones free their nodes and keep their plans. Zooming out fades L1 away. A left click
## on the map outlines that cell, L1's where L1 is drawn, else L2's, and shows its details.
## The town (EcsSitePicker) is picked with the region, sized by the Town option, outlined, and drawn
## into the chunks it covers; a right click moves it to that region cell. Its roads show as lines
## over the region, fading as L1 fades in, where the chunks draw them as floors. Its plots show as
## shaded footprints with their doors, and tinted yards, over the region, fading as L1 shows their
## buildings: walls, rooms, furniture and roofs, which the Roofs box hides. Ore and clay deposits are
## tinted over the region and fade with the roads.

const DEFS := "res://12. Settlement Generator/defs/settlements/"
## The region's land; its child is the L1 land chunks are made of.
const REGION := "res://12. Settlement Generator/defs/lands/region.tres"
## Town sizes: the def that gives the town its area and plaza.
const TOWNS: Array[StringName] = [&"hamlet", &"village", &"town"]
const CHUNK_SIZES: Array[int] = [32, 64, 128]
const WATER_NAMES: Array[String] = ["The region's", "Lake", "River", "Coast", "River to the sea"]
## L1 cells per L2 cell side.
const ZOOM: int = 8
## L1 shows from this zoom (an L1 cell 4 px on screen) and goes below this share of it.
const L1_ZOOM: float = 1.0
const ZOOM_OUT_SHARE: float = 0.75
## Each wheel notch multiplies or divides the zoom by this.
const WHEEL_STEP: float = 1.15
## Seconds a level or chunk takes to fade in or out.
const FADE: float = 0.35
## Worker tasks at once.
const MAX_JOBS: int = 3
## Chunks made round the view, ahead of panning.
const RING: int = 1
## Drawn chunks further than this many chunks outside the view free their nodes.
const KEEP: int = 3
## Ticks a new world is run on the worker before it is shown, so everything is born and drawn.
const SETTLE: int = 3
## Deposit tint by key.
const DEPOSIT_TINTS := {&"iron": Color(0.75, 0.35, 0.2), &"coal": Color(0.1, 0.1, 0.1), &"copper": Color(0.85, 0.5, 0.15),
	&"gold": Color(1.0, 0.85, 0.1), &"clay": Color(0.7, 0.45, 0.35)}
## Footprint tint by role group.
const GROUP_TINTS := {&"home": Color(0.75, 0.45, 0.25), &"elite": Color(0.85, 0.3, 0.3), &"food": Color(0.85, 0.72, 0.3),
	&"farming": Color(0.6, 0.78, 0.3), &"craft": Color(0.55, 0.4, 0.65), &"faith": Color(0.92, 0.9, 0.82),
	&"trade": Color(0.3, 0.5, 0.78), &"entertainment": Color(0.9, 0.45, 0.7), &"works": Color(0.45, 0.45, 0.45)}
## Zone tint, most specific zone first: [zone, colour].
const TINTS := [
	[EcsNodeSpawnDef.Zone.SHALLOW, Color(0.3, 0.9, 1.0)], [EcsNodeSpawnDef.Zone.SHORE, Color(1.0, 0.9, 0.3)],
	[EcsNodeSpawnDef.Zone.ROCK_INNER, Color(0.25, 0.25, 0.3)], [EcsNodeSpawnDef.Zone.ROCK, Color(0.6, 0.6, 0.65)],
	[EcsNodeSpawnDef.Zone.DEEP_FOREST, Color(0.0, 0.3, 0.1)], [EcsNodeSpawnDef.Zone.FOREST_EDGE, Color(0.6, 0.9, 0.3)],
	[EcsNodeSpawnDef.Zone.FOREST, Color(0.2, 0.6, 0.2)],
]

@export var catalog: EcsTownCatalog
@export var entity_catalog: EcsEntityCatalog

@onready var _world_root: Node2D = $World
@onready var _camera: Camera2D = $Camera2D
@onready var _ui: Control = $UI/Root

var _panel: PanelContainer
var _chunk_size: OptionButton
var _town_size: OptionButton
var _water: OptionButton
var _seed: SpinBox
var _generate_button: Button
## What the region or town job is doing, shown as a bar and a line under Generate.
var _progress := EcsProgress.new()
var _progress_bar: ProgressBar
var _progress_label: Label
var _info: Label
var _detail_panel: PanelContainer
var _detail: Label
## The clicked cell's outline, and the cell: {level: 1 or 2, cell}, or {}.
var _marker: Line2D
var _picked: Dictionary = {}
## The town, the reason the last move was refused, and its outlines (area, plaza).
var _site: EcsSettlementSite
var _site_note: String = ""
var _site_lines: Array[Line2D] = []
## The roads drawn over the region, and the region cells a main road passes.
var _roads_layer: Node2D
var _road_l2_cells: Dictionary = {}
## The plots drawn over both levels.
var _plots_layer: Node2D
var _zones_on: bool = false
var _nodes_on: bool = true
var _roofs_on: bool = false
## The region shown: {root, world, scheduler, tile_sync, zones, def, plan, shares, seed, problems}.
var _region: Dictionary = {}
## Counts regions made, so a chunk job for an old one is thrown away.
var _generation: int = 0
## L1: the layer every chunk's root goes under, the chunks, and their L1 def.
var _l1: Node2D
var _chunks: EcsTerrainChunks
var _chunk_def: EcsLandDef
var _in_l1: bool = false
var _l1_tween: Tween
## Worker tasks: id -> job {kind, generation, chunk, stage, work result}.
var _jobs: Dictionary = {}

func _ready() -> void:
	catalog.number()
	# Builds the catalog's lookup here, so the workers only ever read it.
	entity_catalog.has_def(&"tree")
	# Texture arrays touch the renderer, so they're made here and workers only read them.
	for level in [1, 2]:
		catalog.grounds(level)
	catalog.surfaces()
	catalog.pieces()
	_build_panel()
	_build_detail_panel()
	_marker = Line2D.new()
	_marker.closed = true
	_marker.default_color = Color(1.0, 0.85, 0.2)
	_marker.z_index = 30
	_marker.visible = false
	_world_root.add_child(_marker)
	for colour: Color in [Color(1.0, 0.95, 0.6), Color(0.9, 0.5, 0.2)]:
		var line := Line2D.new()
		line.closed = true
		line.default_color = colour
		line.z_index = 29
		line.visible = false
		_world_root.add_child(line)
		_site_lines.append(line)
	_roads_layer = Node2D.new()
	_roads_layer.z_index = 28
	_world_root.add_child(_roads_layer)
	_plots_layer = Node2D.new()
	_plots_layer.z_index = 29
	_plots_layer.draw.connect(_draw_plots)
	_world_root.add_child(_plots_layer)
	_generate()

func _exit_tree() -> void:
	for task: int in _jobs:
		WorkerThreadPool.wait_for_task_completion(task)

func _process(_delta: float) -> void:
	for task: int in _jobs.keys():
		if WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
			var job: Dictionary = _jobs[task]
			_jobs.erase(task)
			_arrived(job)
	_show_progress()
	if _region.is_empty():
		return
	var zoom := _camera.zoom.x
	if not _in_l1 and zoom >= L1_ZOOM:
		_in_l1 = true
		_fade_l1(true)
	elif _in_l1 and zoom < L1_ZOOM * ZOOM_OUT_SHARE:
		_in_l1 = false
		_fade_l1(false)
	if _in_l1:
		var view := _view_cells()
		while _jobs.size() < MAX_JOBS:
			var next := _chunks.next_job(view, RING)
			if next.is_empty():
				break
			_start_chunk(next["chunk"], next["stage"])
		for at in _chunks.far(view, KEEP):
			_undraw(at)
	_report()
	if _marker.visible:
		_marker.width = 3.0 / _camera.zoom.x
	for line in _site_lines:
		line.width = 2.5 / _camera.zoom.x
	if _l1 != null:
		_roads_layer.modulate.a = 1.0 - _l1.modulate.a
		_plots_layer.modulate.a = 1.0 - _l1.modulate.a
		if _region.has("deposits"):
			(_region["deposits"] as Sprite2D).modulate.a = 1.0 - _l1.modulate.a
	for line: Line2D in _roads_layer.get_children():
		line.width = maxf(line.get_meta(&"width", 4.0), line.get_meta(&"screen", 2.0) / _camera.zoom.x)

func _physics_process(delta: float) -> void:
	if _region.is_empty():
		return
	(_region["scheduler"] as EcsScheduler).run_all(_region["world"], delta)
	for at: Vector2i in _chunks.chunks:
		var chunk: Dictionary = _chunks.chunks[at]
		if chunk.has("level"):
			(chunk["level"]["scheduler"] as EcsScheduler).run_all(chunk["level"]["world"], delta)

## The wheel zooms by a factor toward the mouse; the shared camera keeps panning.
func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or get_viewport().gui_get_hovered_control() != null:
		return
	var step := 0.0
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		step = WHEEL_STEP
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		step = 1.0 / WHEEL_STEP
	if step == 0.0:
		return
	get_viewport().set_input_as_handled()
	_zoom_at(get_global_mouse_position(), _camera.zoom.x * step)

## A left click on the map picks the cell under it; a right click moves the town there.
func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or _region.is_empty():
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		_pick(get_global_mouse_position())
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_move_site(EcsTownGrid.cell_at(get_global_mouse_position()))

## Sets the zoom, keeping world point `at` where it is on screen.
func _zoom_at(at: Vector2, zoom: float) -> void:
	var screen := get_viewport().get_canvas_transform() * at
	zoom = clampf(zoom, _camera.min_zoom, _camera.max_zoom)
	_camera.zoom = Vector2(zoom, zoom)
	_camera.position = at - (screen - get_viewport_rect().size * 0.5) / zoom

## What the camera shows, in L1 cells.
func _view_cells() -> Rect2i:
	var half := get_viewport_rect().size * 0.5 / _camera.zoom.x
	var from := (_camera.get_screen_center_position() - half) * ZOOM / EcsTownGrid.CELL
	var to := (_camera.get_screen_center_position() + half) * ZOOM / EcsTownGrid.CELL
	return Rect2i(Vector2i(from.floor()), Vector2i((to - from).ceil()))

func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"DockPanel"
	_panel.position = Vector2(12, 12)
	_panel.custom_minimum_size = Vector2(300, 0)
	_ui.add_child(_panel)
	var box := VBoxContainer.new()
	_panel.add_child(box)
	var title := Label.new()
	title.text = "Settlement terrain"
	title.theme_type_variation = &"DockTitle"
	box.add_child(title)
	_chunk_size = _option(box, "L1 chunk", CHUNK_SIZES.map(func(n: int) -> String: return "%d×%d cells" % [n, n]))
	# 32: each chunk entering the scene costs the engine one short frame; 64 costs some frames 40–70 ms.
	_chunk_size.select(0)
	_chunk_size.item_selected.connect(func(_k: int) -> void: _reset_l1())
	_town_size = _option(box, "Town", TOWNS.map(func(k: StringName) -> String:
		var size := (load(DEFS + "%s.tres" % k) as EcsSettlementDef).size
		return "%s, %d×%d" % [String(k).capitalize(), size.x, size.y]))
	_town_size.select(1)
	_town_size.item_selected.connect(func(_k: int) -> void: _move_site(_site.l2_cell if _site != null else Vector2i(-1, -1)))
	_water = _option(box, "Water", WATER_NAMES)
	var row := HBoxContainer.new()
	box.add_child(row)
	_seed = SpinBox.new()
	_seed.max_value = 1_000_000
	_seed.prefix = "Seed"
	_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_seed)
	var next := Button.new()
	next.text = "Next"
	next.pressed.connect(func() -> void: _seed.value += 1; _generate())
	row.add_child(next)
	var random := Button.new()
	random.text = "Random"
	random.pressed.connect(func() -> void: _seed.value = randi() % 100000; _generate())
	row.add_child(random)
	_generate_button = Button.new()
	_generate_button.text = "Generate"
	_generate_button.pressed.connect(_generate)
	box.add_child(_generate_button)
	_progress_label = Label.new()
	_progress_label.theme_type_variation = &"DockLabel"
	_progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_progress_label.visible = false
	box.add_child(_progress_label)
	_progress_bar = ProgressBar.new()
	_progress_bar.visible = false
	box.add_child(_progress_bar)
	var nodes := CheckBox.new()
	nodes.text = "Nodes"
	nodes.button_pressed = true
	nodes.toggled.connect(func(on: bool) -> void: _nodes_on = on; _show_layers())
	box.add_child(nodes)
	var roofs := CheckBox.new()
	roofs.text = "Roofs"
	roofs.button_pressed = _roofs_on
	roofs.toggled.connect(func(on: bool) -> void: _roofs_on = on; _show_layers())
	box.add_child(roofs)
	var zones := CheckBox.new()
	zones.text = "Zone tint"
	zones.toggled.connect(func(on: bool) -> void: _zones_on = on; _show_layers())
	box.add_child(zones)
	_info = Label.new()
	_info.theme_type_variation = &"DockLabel"
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_info)
	# The panel eats the mouse, so a click, scroll or drag over it never reaches the map or camera.
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouse:
			_panel.accept_event())

## The cell panel, top right; hidden until a cell is picked.
func _build_detail_panel() -> void:
	_detail_panel = PanelContainer.new()
	_detail_panel.theme_type_variation = &"DockPanel"
	_detail_panel.custom_minimum_size = Vector2(280, 0)
	_detail_panel.anchor_left = 1.0
	_detail_panel.anchor_right = 1.0
	_detail_panel.offset_left = -292.0
	_detail_panel.offset_right = -12.0
	_detail_panel.offset_top = 12.0
	_detail_panel.visible = false
	_detail_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_ui.add_child(_detail_panel)
	var box := VBoxContainer.new()
	_detail_panel.add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	var title := Label.new()
	title.text = "Cell"
	title.theme_type_variation = &"DockTitle"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.pressed.connect(func() -> void: _picked = {}; _marker.visible = false; _detail_panel.visible = false)
	row.add_child(close)
	_detail = Label.new()
	_detail.theme_type_variation = &"DockLabel"
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_detail)

## Picks the cell at `at` (world position): L1's where its chunk is drawn and L1 shows, else L2's.
func _pick(at: Vector2) -> void:
	var l1 := EcsTownGrid.cell_at(at * ZOOM)
	var chunk: Dictionary = _chunks.chunks.get(_chunks.chunk_at(l1), {})
	var region := _region["def"] as EcsLandDef
	var size := float(EcsTownGrid.CELL)
	if _in_l1 and chunk.get("drawn", false):
		_picked = {"level": 1, "cell": l1}
		size /= ZOOM
	else:
		var cell := EcsTownGrid.cell_at(at)
		if not Rect2i(Vector2i.ZERO, region.size).has_point(cell):
			return
		_picked = {"level": 2, "cell": cell}
	var corner := Vector2(_picked["cell"] as Vector2i) * size
	_marker.points = PackedVector2Array([corner, corner + Vector2(size, 0), corner + Vector2(size, size), corner + Vector2(0, size)])
	_marker.visible = true
	_detail_panel.visible = true
	_describe()

## The picked cell's details, refreshed as its chunk is made.
func _describe() -> void:
	if _picked.is_empty():
		return
	var cell: Vector2i = _picked["cell"]
	var region := _region["def"] as EcsLandDef
	var plan := _region["plan"] as Dictionary
	var lines := PackedStringArray()
	if _picked["level"] == 2:
		var i := cell.y * region.size.x + cell.x
		var kind: int = (plan["kinds"] as PackedByteArray)[i]
		lines.append("L2 cell %s, 8 m a side" % cell)
		lines.append("Ground: %s%s" % [EcsTerrainGenerator.TERRAIN_KEYS[kind],
			", river" if (plan["river"] as PackedByteArray)[i] != 0 else (", sea" if kind == EcsTerrainGenerator.WATER else "")])
		lines.append("Zones: %s" % _zone_names((plan["zones"] as PackedByteArray)[i]))
		lines.append("Walk cost: %s" % _walk_cost(kind))
		lines.append("Holds L1 cells %s to %s" % [cell * ZOOM, cell * ZOOM + Vector2i(ZOOM - 1, ZOOM - 1)])
		var deposit: int = (plan["deposits"]["ids"] as PackedByteArray)[i]
		if deposit != 0:
			lines.append("Deposit: %s" % plan["deposits"]["keys"][deposit - 1])
		if _road_l2_cells.has(cell):
			lines.append("A main road passes through")
		if _site != null and cell == _site.l2_cell:
			lines.append("The town's site: " + _town_line().split("score ")[1].split("\n")[0])
		elif _site != null and Rect2i(_site.area.position / ZOOM, _site.area.size / ZOOM).has_point(cell):
			lines.append("In the town's area")
	else:
		var at := _chunks.chunk_at(cell)
		var chunk: Dictionary = _chunks.chunks.get(at, {})
		var local := cell - at * _chunks.size
		var parent := Vector2i((Vector2(cell) / ZOOM).floor())
		lines.append("L1 cell %s, 1 m a side" % cell)
		lines.append("Chunk %s, cell %s in it" % [at, local])
		if chunk.has("terrain"):
			var outer := _chunks.size + 2
			var kind: int = (chunk["terrain"]["kinds"] as PackedByteArray)[(local.y + 1) * outer + local.x + 1]
			lines.append("Ground: %s%s" % [EcsTerrainGenerator.TERRAIN_KEYS[kind],
				", river" if (chunk["terrain"]["river"] as PackedByteArray)[(local.y + 1) * outer + local.x + 1] != 0 else ""])
			lines.append("Zones: %s" % _zone_names((chunk["terrain"]["zones"] as PackedByteArray)[local.y * _chunks.size + local.x]))
			lines.append("Walk cost: %s" % _walk_cost(kind))
		lines.append("Object: %s" % _object_at(chunk, local))
		if _site != null and _site.plot_at.has(cell):
			var k: int = _site.plot_at[cell]
			var plot := _site.plots[k]
			var rect: Rect2i = plot["footprint"]
			var role := EcsTownCensus.CATALOG.role(plot["role"])
			lines.append("Town: plot %d, %s: its %s; footprint %d×%d, door at %s facing %s" % [k, role.display_name,
				"door" if cell == plot["door"] else ("footprint" if rect.has_point(cell) else
					(String(plot.get("annex_kind", "yard")) if (plot.get("annex", Rect2i()) as Rect2i).has_point(cell) else "yard")), rect.size.x, rect.size.y,
				plot["door"], {Vector2i.RIGHT: "east", Vector2i.DOWN: "south", Vector2i.LEFT: "west", Vector2i.UP: "north"}[plot["front"]]])
			if plot.has("building"):
				var built: Dictionary = plot["building"]
				lines.append("Building: %s, %s, %s shape" % [built["type"], ["poor", "middling", "rich"][built["wealth"]], built["shape"]])
				var room := _room_name(cell)
				if room != "":
					lines.append("Room: " + room)
		elif _site != null and _site.road_cells.has(cell):
			lines.append("Town: %s" % {&"main": "main road", &"lane": "lane", &"track": "track to an outlying work", &"bridge": "bridge (wood over water)"}[_site.road_cells[cell]])
		elif _site != null:
			if cell == _site.well:
				lines.append("Town: the well")
			elif _site.plaza.has_point(cell):
				lines.append("Town: the plaza (stone floor)")
			elif _site.cleared.any(func(r: Rect2i) -> bool: return r.has_point(cell)):
				lines.append("Town: cleared ground round the plaza")
			elif _site.area.has_point(cell):
				lines.append("Town: in its area")
		var parent_deposit: int = (plan["deposits"]["ids"] as PackedByteArray)[parent.y * region.size.x + parent.x]
		if parent_deposit != 0:
			lines.append("In a %s deposit" % plan["deposits"]["keys"][parent_deposit - 1])
		lines.append("In L2 cell %s: %s" % [parent, EcsTerrainGenerator.TERRAIN_KEYS[(plan["kinds"] as PackedByteArray)[parent.y * region.size.x + parent.x]]])
		var made := PackedStringArray()
		for step: Array in [["terrain", chunk.has("terrain")], ["drawn", chunk.get("drawn", false)],
				["objects", chunk.has("nodes")], ["objects drawn", chunk.get("objects_drawn", false)]]:
			if step[1]:
				made.append(step[0])
		lines.append("Chunk made: %s" % (", ".join(made) if not made.is_empty() else "nothing yet"))
	_detail.text = "\n".join(lines)

## The room L1 detected at `cell` in its chunk's world, or "".
func _room_name(cell: Vector2i) -> String:
	var at := _chunks.chunk_at(cell)
	var chunk: Dictionary = _chunks.chunks.get(at, {})
	if not chunk.has("level"):
		return ""
	var level: Dictionary = chunk["level"]
	var grid := level["grid"] as EcsTownGridSingleton
	var local := cell - at * _chunks.size + Vector2i.ONE
	var building := (level["world"] as EcsWorld).get_component(grid.building_id[EcsTownGrid.index(grid, local)], EcsBuildingComponent) \
		as EcsBuildingComponent if grid.building_id[EcsTownGrid.index(grid, local)] > EcsWorld.NO_ENTITY else null
	if building == null:
		return ""
	for room: Dictionary in building.rooms:
		if (room["cells"] as Array).has(local):
			return room["label"] if room["label"] != "" else ("sealed" if room["sealed"] else "untyped")
	return ""

func _town_line() -> String:
	var note := "" if _site_note == "" else "\n" + _site_note
	if _site == null:
		return "No town" + note
	var score := _site.score
	var counts := {&"main": 0, &"lane": 0, &"track": 0, &"bridge": 0}
	for kind: StringName in _site.road_cells.values():
		counts[kind] += 1
	var lanes := _site.roads.filter(func(r: Dictionary) -> bool: return r["kind"] == &"lane").size()
	return "Town at region cell %s, score %.2f (water %.2f, open %.2f, room %.2f, river %.2f)\nRoads: %d exits, %d m of main road, %d lanes (%d m), %d m of track, %d bridge%s\nPlots: %d, %d of them outlying in %d window%s%s%s" % [_site.l2_cell,
		score["total"], score["water"], score["open"], score["room"], score["river"], _site.exits.size(),
		counts[&"main"] / _town_def().main_width, lanes, counts[&"lane"], counts[&"track"], _site.bridges, "" if _site.bridges == 1 else "s",
		_site.plots.size(), _site.plots.filter(func(p: Dictionary) -> bool:
			return Vector2((p["footprint"] as Rect2i).get_center()).distance_to(Vector2(_site.well)) > _site.radius).size(),
		_site.outlying.size(), "" if _site.outlying.size() == 1 else "s", _economy_line(), note]

## The census, for the info panel: what the town lives on, its people, traffic, resources and buildings.
func _economy_line() -> String:
	var economy := _site.economy
	if economy.is_empty():
		return ""
	var catalog: EcsEconomyCatalog = EcsTownCensus.CATALOG
	var main := "none"
	for c in catalog.characters:
		if c.key == economy["character"]:
			main = c.display_name
	var rich := [0, 0, 0]
	var at_work := 0
	for family: Dictionary in economy["families"]:
		rich[family["wealth"]] += 1
		at_work += 1 if family["home"] == &"work" else 0
	var resources := PackedStringArray()
	for key: StringName in economy["resources"]:
		var r: Dictionary = economy["resources"][key]
		if r["need"] > 0.0 or r["made"] > 0.0:
			resources.append("%s %d/%d%s" % [catalog.resource(key).display_name, roundi(r["made"]), roundi(r["need"]),
				" +%d sold" % roundi(r["exported"]) if r["exported"] > 0.0 else ""])
	var built := PackedStringArray()
	for entry: Dictionary in economy["roles"]:
		built.append("%d %s" % [entry["count"], catalog.role(entry["role"]).display_name])
	var survey := PackedStringArray()
	for key: StringName in _site.survey:
		if _site.survey[key] >= EcsResourceSurvey.PRESENT:
			survey.append("%s %.1f" % [key, _site.survey[key]])
	var short := PackedStringArray()
	for entry: Dictionary in economy.get("short", []):
		short.append("%d %s" % [entry["count"], catalog.role(entry["role"]).display_name])
	var traffic: Dictionary = economy["traffic"]
	return "\nLives on: %s; traffic %s (%d travellers a day)\nPeople: %d in %d families (%d poor, %d middling, %d rich; %d live at work), %d labourers spare%s\nMade/needed: %s\nIn reach: %s\nBuildings: %s%s" % [
		main, traffic["name"], traffic["travellers"], economy["population"], (economy["families"] as Array).size(), rich[0], rich[1],
		rich[2], at_work, economy["labourers"], "" if economy["short_of_workers"] <= 0 else ", %d workers short" % economy["short_of_workers"],
		", ".join(resources), ", ".join(survey), ", ".join(built), "" if short.is_empty() else "\nShort, no room: " + ", ".join(short)]

func _zone_names(bits: int) -> String:
	var names := PackedStringArray()
	for zone in EcsNodeSpawnDef.Zone.size():
		if bits & (1 << zone):
			names.append(String(EcsNodeSpawnDef.Zone.keys()[zone]).to_lower().replace("_", " "))
	return ", ".join(names) if not names.is_empty() else "none"

func _walk_cost(kind: int) -> String:
	var cost := catalog.terrain(catalog.terrain_id(EcsTerrainGenerator.TERRAIN_KEYS[kind])).walk_cost
	return "can't be walked" if cost <= 0.0 else "%.1f" % cost

## What stands on `local` in `chunk`: a node covering it, its kind and what it gives.
func _object_at(chunk: Dictionary, local: Vector2i) -> String:
	if not chunk.has("nodes"):
		return "not planned yet"
	for node: Dictionary in chunk["nodes"]:
		if Rect2i(node["cell"], node["size"]).has_point(local):
			var def := entity_catalog.get_def(node["blueprint"])
			var source := def.template(&"resource_node") as EcsResourceNodeComponent
			var size: Vector2i = node["size"]
			return "%s (%s, gives %s)%s" % [def.display_name, source.kind, String(source.gives).replace("_", " "),
				"" if size == Vector2i.ONE else ", %d×%d from %s" % [size.x, size.y, node["cell"]]]
	return "none"

func _option(box: VBoxContainer, label: String, items: Array) -> OptionButton:
	var row := HBoxContainer.new()
	box.add_child(row)
	var name := Label.new()
	name.text = label
	name.custom_minimum_size = Vector2(60, 0)
	row.add_child(name)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL	
	for item: String in items:
		option.add_item(item)
	row.add_child(option)
	return option

## Plans the region from the inputs, and builds its world, on a worker thread.
func _generate() -> void:
	for job: Dictionary in _jobs.values():
		if job["kind"] == &"region":
			return
	var def := (load(REGION) as EcsLandDef).duplicate() as EcsLandDef
	if _water.selected > 0 and _water.selected - 1 != def.water:
		def.water = _water.selected - 1
		def.water_share = 0.03 if def.water == EcsLandDef.Water.RIVER else (0.18 if def.water == EcsLandDef.Water.RIVER_TO_SEA else 0.12)
	var rng_seed := int(_seed.value)
	var town := _town_def()
	_generation += 1
	_generate_button.disabled = true
	var progress := EcsProgress.new()
	_progress = progress
	_start({"kind": &"region"}, func() -> Dictionary:
		# Shares of the bar by measured time: the plan ~0.2 s, the region's tiles ~2 s, the town ~3.5 s.
		progress.within(0.0, 0.05)
		var plan := EcsTerrainGenerator.plan(def, rng_seed, catalog, entity_catalog, progress)
		progress.within(0.05, 0.42)
		progress.report("Building the region's tiles")
		var level := _make_level(def.size, plan["commands"], Vector2.ZERO, 1.0, false)
		progress.report("Checking the terrain", 0.95)
		var shares := EcsTerrainGenerator.blend_shares(plan, def)
		var problems := EcsTerrainCheck.problems(def, plan)
		var tint := _tint(def.size, plan["zones"])
		progress.within(0.42, 1.0)
		var site := EcsSitePicker.pick(plan, def, town, rng_seed, ZOOM, catalog, shares, progress)
		progress.within(0.0, 1.0)
		progress.report("Showing the region", 1.0)
		level.merge({"def": def, "plan": plan, "seed": rng_seed, "problems": problems, "shares": shares, "tint": tint, "site": site})
		return level)

func _town_def() -> EcsSettlementDef:
	return load(DEFS + "%s.tres" % TOWNS[_town_size.selected]) as EcsSettlementDef

## Re-sites the town on a worker: at region cell `cell`, or the best site when `cell` is (-1, -1).
func _move_site(cell: Vector2i) -> void:
	if _region.is_empty():
		return
	for job: Dictionary in _jobs.values():
		if job["kind"] == &"site" or job["kind"] == &"region":
			return
	var plan: Dictionary = _region["plan"]
	var region: EcsLandDef = _region["def"]
	var shares: Array = _region["shares"]
	var rng_seed: int = _region["seed"]
	var town := _town_def()
	_site_note = "Placing the town…"
	var progress := EcsProgress.new()
	_progress = progress
	_start({"kind": &"site"}, func() -> Dictionary:
		if cell == Vector2i(-1, -1):
			var site := EcsSitePicker.pick(plan, region, town, rng_seed, ZOOM, catalog, shares, progress)
			return {"site": site} if site != null else {"refused": "no site on this region"}
		return EcsSitePicker.place(plan, region, town, cell, rng_seed, ZOOM, catalog, shares, progress))

## Puts `site` over the chunks: those under the old or new town, its outlying windows and its roads
## lose their objects and drawing (their terrain stays) and are made again with it; any of their
## jobs still running is thrown away.
func _set_site(site: EcsSettlementSite) -> void:
	var affected: Array[Vector2i] = []
	for old in [_chunks.site, site]:
		if old == null:
			continue
		var town := old as EcsSettlementSite
		affected.append_array(_chunks.touching(town.area))
		for window: Dictionary in town.outlying:
			affected.append_array(_chunks.touching(window["rect"]))
		# Roads and tracks run past the area; their floors and borders are in these chunks too.
		var under: Dictionary = {}
		for cell: Vector2i in town.road_cells:
			for at in _chunks.touching(Rect2i(cell, Vector2i.ONE)):
				under[at] = true
		for at: Vector2i in under:
			affected.append(at)
	_site = site
	_chunks.site = site
	for at in affected:
		var chunk: Dictionary = _chunks.chunks.get(at, {})
		if chunk.is_empty():
			continue
		chunk["rev"] = int(chunk.get("rev", 0)) + 1
		chunk["busy"] = false
		chunk.erase("nodes")
		if chunk.has("level"):
			(chunk["level"]["root"] as Node2D).queue_free()
			chunk.erase("level")
		chunk["drawn"] = false
		chunk["objects_drawn"] = false
	_outline_site()

## Draws the town's roads over the region: main roads thick, bridges light, lanes thin, exits marked.
func _draw_roads() -> void:
	for child in _roads_layer.get_children():
		child.queue_free()
	_road_l2_cells.clear()
	if _site == null:
		return
	var px := float(EcsTownGrid.CELL) / ZOOM
	for road: Dictionary in _site.roads:
		var main: bool = road["kind"] == &"main"
		# Split into runs on land and runs over bridges; each run starts where the last ended.
		var runs: Array = []
		var run := PackedVector2Array()
		var on_bridge := false
		for point: Vector2 in road["points"]:
			var bridge: bool = _site.road_cells.get(Vector2i(point.round()), &"") == &"bridge"
			var at := (point + Vector2(0.5, 0.5)) * px
			if bridge != on_bridge and not run.is_empty():
				runs.append([on_bridge, run])
				run = PackedVector2Array([run[run.size() - 1]])
			on_bridge = bridge
			run.append(at)
		runs.append([on_bridge, run])
		for run_of: Array in runs:
			var run_points := run_of[1] as PackedVector2Array
			if run_points.size() < 2:
				continue
			var line := Line2D.new()
			line.points = run_points
			var track: bool = road["kind"] == &"track"
			line.default_color = Color(0.85, 0.75, 0.55) if run_of[0] else (Color(0.45, 0.3, 0.18) if main else (Color(0.7, 0.6, 0.45) if track else Color(0.6, 0.45, 0.3)))
			line.set_meta(&"width", road["width"] * px)
			line.set_meta(&"screen", 3.0 if main else 1.5)
			_roads_layer.add_child(line)
		if main:
			for point: Vector2 in road["l2_points"]:
				_road_l2_cells[Vector2i(point.round())] = true
	for exit in _site.exits:
		var mark := Line2D.new()
		var at := (Vector2(exit) + Vector2(0.5, 0.5)) * EcsTownGrid.CELL
		mark.points = PackedVector2Array([at + Vector2(-24, -24), at + Vector2(24, 24), at, at + Vector2(-24, 24), at + Vector2(24, -24)])
		mark.default_color = Color(0.9, 0.2, 0.15)
		mark.set_meta(&"width", 6.0)
		mark.set_meta(&"screen", 3.0)
		_roads_layer.add_child(mark)

## The town's plots: yards tinted, footprints shaded by role group, doors marked (ringed for a shop
## front); outlying windows outlined; each group's district point a disc of its tint.
func _draw_plots() -> void:
	if _site == null:
		return
	var px := float(EcsTownGrid.CELL) / ZOOM
	for plot: Dictionary in _site.plots:
		for cell: Vector2i in plot["yard"]:
			_plots_layer.draw_rect(Rect2(Vector2(cell) * px, Vector2(px, px)), Color(0.55, 0.75, 0.3, 0.35))
		if plot.has("annex"):
			var annex: Rect2i = plot["annex"]
			var tint := Color(0.72, 0.6, 0.3, 0.6) if plot["annex_kind"] == &"field" else Color(0.55, 0.7, 0.35, 0.6)
			_plots_layer.draw_rect(Rect2(Vector2(annex.position) * px, Vector2(annex.size) * px), tint)
		if plot.has("dock"):
			for cell: Vector2i in plot["dock"]["cells"]:
				_plots_layer.draw_rect(Rect2(Vector2(cell) * px, Vector2(px, px)), Color(0.6, 0.42, 0.25, 0.9))
		var rect: Rect2i = plot["footprint"]
		var group := EcsTownCensus.CATALOG.role(plot["role"]).group
		_plots_layer.draw_rect(Rect2(Vector2(rect.position) * px, Vector2(rect.size) * px), Color(GROUP_TINTS.get(group, Color.MAGENTA), 0.8))
		_plots_layer.draw_rect(Rect2(Vector2(plot["door"] as Vector2i) * px, Vector2(px, px)), Color(0.2, 0.1, 0.05))
		if plot.get("sells", &"") == &"home":
			_plots_layer.draw_circle((Vector2(plot["door"] as Vector2i) + Vector2(0.5, 0.5)) * px, px * 1.2, Color(1, 1, 1), false, px * 0.5)
	for window: Dictionary in _site.outlying:
		var rect: Rect2i = window["rect"]
		_plots_layer.draw_rect(Rect2(Vector2(rect.position) * px, Vector2(rect.size) * px), Color(0.9, 0.5, 0.2), false, px)
	var points: Dictionary = _site.quarters.get("points", {})
	for group: StringName in points:
		var at := (Vector2(points[group] as Vector2i) + Vector2(0.5, 0.5)) * px
		_plots_layer.draw_circle(at, px * 4.0, Color(GROUP_TINTS.get(group, Color.MAGENTA), 0.9))
		_plots_layer.draw_circle(at, px * 4.0, Color(0.1, 0.1, 0.1), false, px)

## Outlines the town's reach (a circle round the well: the town has no box) and its plaza over the region.
func _outline_site() -> void:
	var px := float(EcsTownGrid.CELL) / ZOOM
	for k in _site_lines.size():
		_site_lines[k].visible = _site != null and k < 2
	if _site == null:
		return
	var ring := PackedVector2Array()
	for k in 49:
		ring.append((Vector2(_site.well) + Vector2.from_angle(k * TAU / 48.0) * _site.radius) * px)
	_site_lines[0].points = ring
	var rect := Rect2(Vector2(_site.plaza.position) * px, Vector2(_site.plaza.size) * px)
	_site_lines[1].points = PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	_draw_roads()
	_plots_layer.queue_redraw()

## Starts chunk `at`'s `stage` on a worker.
func _start_chunk(at: Vector2i, stage: int) -> void:
	if not _chunks.chunks.has(at):
		_chunks.chunks[at] = {}
	var chunk: Dictionary = _chunks.chunks[at]
	var size := _chunks.size
	var job := {"kind": &"chunk", "chunk": at, "stage": stage, "rev": int(chunk.get("rev", 0))}
	match stage:
		EcsTerrainChunks.Stage.TERRAIN:
			var parent: Dictionary = _region["plan"]
			var region: EcsLandDef = _region["def"]
			var shares: Array = _region["shares"]
			var rng_seed: int = _region["seed"]
			var shore := _chunk_def.shore_width
			chunk["busy"] = true
			_start(job, func() -> Dictionary:
				return EcsTerrainGenerator.refine_terrain(parent, region, Vector2i(size, size), shore, at * size, ZOOM,
					rng_seed, 1, shares))
		EcsTerrainChunks.Stage.DRAW_TERRAIN, EcsTerrainChunks.Stage.DRAW_OBJECTS:
			var kinds: PackedByteArray = chunk["terrain"]["kinds"]
			var nodes: Array = chunk["nodes"] if stage == EcsTerrainChunks.Stage.DRAW_OBJECTS else []
			var town := _chunks.overlay(at, stage == EcsTerrainChunks.Stage.DRAW_OBJECTS)
			var origin := Vector2(at * size - Vector2i.ONE) * EcsTownGrid.CELL / ZOOM
			chunk["busy"] = true
			_start(job, func() -> Dictionary:
				var outer := Vector2i(size, size) + Vector2i(2, 2)
				var commands := EcsTerrainGenerator.terrain_commands(kinds, outer, Vector2i.ZERO, catalog)
				# A chunk's cells sit one in from its border, which is its neighbours'.
				for node: Dictionary in nodes:
					commands.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT,
						(node["cell"] as Vector2i) + Vector2i.ONE, node["blueprint"], 0))
				commands.append_array(town)
				return _make_level(outer, commands, origin, 1.0 / ZOOM, true))
		EcsTerrainChunks.Stage.OBJECTS:
			var zones: PackedByteArray = chunk["terrain"]["zones"]
			var deposits: Dictionary = chunk["terrain"]["deposits"]
			var def := _chunk_def
			var rng_seed: int = _region["seed"]
			var blocked := _chunks.blocked(at)
			chunk["busy"] = true
			_start(job, func() -> Dictionary:
				return {"nodes": EcsTerrainGenerator.refine_nodes(def, zones, rng_seed, at, entity_catalog, blocked, deposits)})

func _start(job: Dictionary, work: Callable) -> void:
	job["generation"] = _generation
	var task := WorkerThreadPool.add_task(func() -> void: job["result"] = work.call(), false, "settlement terrain")
	_jobs[task] = job

## A world of `size` through module 10's pipeline, run until settled, under a root placed at `at`
## and scaled by `scale`, built off the scene tree. `trim` erases the outer ring of ground tiles,
## which show cells past the edge: a chunk's border cells are its neighbours', so the ring left is
## drawn the same by both and shows no seam. Runs on a worker.
func _make_level(size: Vector2i, commands: Array[EcsBuildCommand], at: Vector2, scale: float, trim: bool) -> Dictionary:
	var started := Time.get_ticks_usec()
	var root := Node2D.new()
	root.position = at
	root.scale = Vector2(scale, scale)
	var tiles := Node2D.new()
	root.add_child(tiles)
	var entities := Node2D.new()
	root.add_child(entities)
	var world := EcsWorld.new()
	var grid := EcsTownGrid.make(size.x, size.y, catalog.terrain_id(&"grass"))
	grid.commands.append_array(commands)
	world.add_singleton(grid)
	world.add_singleton(EcsLifecycleSingleton.new())
	world.add_singleton(EcsTownNavSingleton.new())
	var tile_sync := EcsTileSyncSystem.new(tiles, catalog)
	tile_sync.level = 2 if scale >= 1.0 else 1  # the region is L2, chunks L1
	var scheduler := EcsScheduler.new()
	scheduler \
		.add(EcsLifecycleSystem.new(EcsEntityManager.new(entities), entity_catalog)) \
		.add(EcsBuildCommandSystem.new(catalog, entity_catalog)) \
		.add(EcsTownNavSystem.new(catalog)) \
		.add(EcsRoomDetectionSystem.new(catalog)) \
		.add(EcsRoofSystem.new(catalog)) \
		.add(tile_sync)
	for tick in SETTLE:
		scheduler.run_all(world, 1.0 / 60.0)
	# Every chunk's ground reaches half a cell into its neighbours, so pieces draw above all ground.
	for layer: TileMapLayer in [tile_sync.furniture_layer(), tile_sync.door_layer(), tile_sync.wall_layer(), tile_sync.post_layer(), tile_sync.attachment_layer()]:
		layer.z_index = 1
	# Roofs cover the building, pieces and walls included, when shown.
	for layer in tile_sync.roof_layers():
		layer.z_index = 2
	if trim:
		for layer in tile_sync.roof_layers():
			for x in size.x + 1:
				layer.erase_cell(Vector2i(x, 0))
				layer.erase_cell(Vector2i(x, size.y))
			for y in size.y + 1:
				layer.erase_cell(Vector2i(0, y))
				layer.erase_cell(Vector2i(size.x, y))
	return {"root": root, "world": world, "scheduler": scheduler, "tile_sync": tile_sync, "grid": grid,
		"build_usec": Time.get_ticks_usec() - started}

## What a worker made goes into the scene, unless it was for a region since replaced.
func _arrived(job: Dictionary) -> void:
	var result: Dictionary = job["result"]
	if job["kind"] == &"region":
		_generate_button.disabled = false
		_show_region(result)
		return
	if job["generation"] != _generation:
		if result.has("root"):
			(result["root"] as Node2D).free()
		return
	if job["kind"] == &"site":
		_site_note = result.get("refused", "")
		if result.has("site"):
			_set_site(result["site"])
		return
	var at: Vector2i = job["chunk"]
	var chunk: Dictionary = _chunks.chunks[at]
	if job["rev"] != int(chunk.get("rev", 0)):
		if result.has("root"):
			(result["root"] as Node2D).free()
		return
	chunk["busy"] = false
	match job["stage"]:
		EcsTerrainChunks.Stage.TERRAIN:
			chunk["terrain"] = result
		EcsTerrainChunks.Stage.DRAW_TERRAIN, EcsTerrainChunks.Stage.DRAW_OBJECTS:
			# With objects, it fades in over the terrain-only chunk, which goes once it is covered.
			var old: Node2D = chunk["level"]["root"] if chunk.has("level") else null
			chunk["level"] = result
			chunk["drawn"] = true
			chunk["objects_drawn"] = job["stage"] == EcsTerrainChunks.Stage.DRAW_OBJECTS
			var root := result["root"] as Node2D
			root.modulate.a = 0.0
			_l1.add_child(root)
			var tween := create_tween()
			tween.tween_property(root, "modulate:a", 1.0, FADE)
			if old != null:
				tween.tween_callback(old.queue_free)
			_show_layers()
		EcsTerrainChunks.Stage.OBJECTS:
			chunk["nodes"] = result["nodes"]

## Frees a far chunk's nodes and world; its terrain and node plans stay, so it is only redrawn.
func _undraw(at: Vector2i) -> void:
	var chunk: Dictionary = _chunks.chunks[at]
	(chunk["level"]["root"] as Node2D).queue_free()
	chunk.erase("level")
	chunk["drawn"] = false
	chunk["objects_drawn"] = false

func _show_region(level: Dictionary) -> void:
	if not _region.is_empty():
		(_region["root"] as Node2D).queue_free()
	var zones := Sprite2D.new()
	zones.texture = ImageTexture.create_from_image(level["tint"])
	zones.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	zones.centered = false
	zones.z_index = 20
	zones.scale = Vector2(EcsTownGrid.CELL, EcsTownGrid.CELL)
	(level["root"] as Node2D).add_child(zones)
	level["zones"] = zones
	var deposits := Sprite2D.new()
	deposits.texture = ImageTexture.create_from_image(_deposit_tint(level["def"], level["plan"]["deposits"]))
	deposits.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	deposits.centered = false
	deposits.z_index = 21
	deposits.scale = Vector2(EcsTownGrid.CELL, EcsTownGrid.CELL)
	(level["root"] as Node2D).add_child(deposits)
	level["deposits"] = deposits
	_region = level
	_world_root.add_child(level["root"])
	_site = level["site"]
	_site_note = "" if _site != null else "No site for a town on this region"
	_reset_l1()
	_frame()
	_show_layers()

## The region's deposits as an image, a cell a pixel, each tinted by its key.
func _deposit_tint(def: EcsLandDef, deposits: Dictionary) -> Image:
	var image := Image.create(def.size.x, def.size.y, false, Image.FORMAT_RGBA8)
	var ids := deposits["ids"] as PackedByteArray
	var keys := deposits["keys"] as Array
	for i in ids.size():
		if ids[i] != 0:
			var tint: Color = DEPOSIT_TINTS.get(keys[ids[i] - 1], Color.MAGENTA)
			image.set_pixel(i % def.size.x, i / def.size.x, Color(tint, 0.7))
	return image

## The bar and line under Generate: the region or town job's stage while one runs, else, at L1,
## how many chunks in view are made; hidden when nothing is under way.
func _show_progress() -> void:
	var stage := ""
	var done := 0.0
	var working := false
	for job: Dictionary in _jobs.values():
		working = working or job["kind"] == &"region" or job["kind"] == &"site"
	if working:
		var read := _progress.read()
		stage = read[0] if read[0] != "" else "Starting"
		done = read[1]
	elif _in_l1 and _chunks != null:
		var visible := _chunks.around(_view_cells(), 0)
		var made := 0
		for at in visible:
			made += 1 if (_chunks.chunks.get(at, {}) as Dictionary).get("objects_drawn", false) else 0
		if made < visible.size():
			stage = "Streaming L1 ground into view: %d of %d chunks made" % [made, visible.size()]
			done = float(made) / visible.size()
	_progress_label.visible = stage != ""
	_progress_bar.visible = stage != ""
	_progress_label.text = stage
	_progress_bar.value = done * 100.0

## Drops every chunk and starts L1 afresh, for a new region or chunk size.
func _reset_l1() -> void:
	if _region.is_empty():
		return
	_generation += 1
	if _l1 != null:
		_l1.queue_free()
	_l1 = Node2D.new()
	_l1.modulate.a = 1.0 if _in_l1 else 0.0
	_world_root.add_child(_l1)
	_chunks = EcsTerrainChunks.new((_region["def"] as EcsLandDef).size, ZOOM, CHUNK_SIZES[_chunk_size.selected])
	_chunk_def = ((_region["def"] as EcsLandDef).child).duplicate() as EcsLandDef
	_chunk_def.size = Vector2i(_chunks.size, _chunks.size)
	_chunks.site = _site
	_outline_site()
	_picked = {}
	_marker.visible = false
	_detail_panel.visible = false
	_in_l1 = false
	_l1.modulate.a = 0.0

func _fade_l1(show: bool) -> void:
	if _l1_tween != null:
		_l1_tween.kill()
	_l1_tween = create_tween()
	_l1_tween.tween_property(_l1, "modulate:a", 1.0 if show else 0.0, FADE)

## The nodes and zone tint toggles, on the region and every drawn chunk.
func _show_layers() -> void:
	var levels: Array = [_region]
	if _chunks != null:
		for at: Vector2i in _chunks.chunks:
			if _chunks.chunks[at].has("level"):
				levels.append(_chunks.chunks[at]["level"])
	for level: Dictionary in levels:
		if level.is_empty():
			continue
		var sync := level["tile_sync"] as EcsTileSyncSystem
		sync.furniture_layer().visible = _nodes_on
		sync.attachment_layer().visible = _nodes_on
		sync.roofs_visible = _roofs_on
	if _region.has("zones"):
		(_region["zones"] as Sprite2D).visible = _zones_on

## The zone tint: one pixel per cell, to scale to the grid.
func _tint(size: Vector2i, zones: PackedByteArray) -> Image:
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	for i in size.x * size.y:
		for tint: Array in TINTS:
			if zones[i] & (1 << int(tint[0])):
				var colour: Color = tint[1]
				colour.a = 0.55
				image.set_pixel(i % size.x, i / size.x, colour)
				break
	return image

## Zooms and centres the camera so the whole region fills the view right of the panel.
func _frame() -> void:
	var left := _panel.get_rect().end.x + 12.0
	var span := Vector2((_region["def"] as EcsLandDef).size * EcsTownGrid.CELL)
	var view := get_viewport_rect().size
	var room := Vector2(view.x - left, view.y)
	var zoom := minf(room.x / span.x, room.y / span.y)
	_camera.zoom = Vector2(zoom, zoom)
	_camera.position = span * 0.5 - Vector2(left * 0.5 / zoom, 0)

func _report() -> void:
	var region := _region["def"] as EcsLandDef
	var problems := _region["problems"] as Array[String]
	var tally := _chunks.tally()
	var lines := PackedStringArray([
		"L2 region %d×%d at 8 m a cell, %s, seed %d" % [region.size.x, region.size.y,
			WATER_NAMES[region.water + 1].to_lower(), _region["seed"]],
		"Sound" if problems.is_empty() else "Problems: " + "; ".join(problems),
		_town_line(),
		"Zoom ×%.2f: %s" % [_camera.zoom.x, "L1, 1 m a cell" if _in_l1 else "L2 (L1 from ×%.2f)" % L1_ZOOM],
		"L1 chunks of %d×%d, %d×%d across the region" % [_chunks.size, _chunks.size, _chunks.count.x, _chunks.count.y],
		"Terrain planned %d, drawn %d; objects planned %d, drawn %d" % [tally[0], tally[1], tally[2], tally[3]],
		"Worker jobs running %d" % _jobs.size(),
	])
	_info.text = "\n".join(lines)
	_describe()
