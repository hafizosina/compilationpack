extends Node2D

## Module 13's viewer: a world in three map levels, each with its own locked zoom. L3 is the world
## (64 m a cell, drawn at scale 1), L2 its regions (8 m, at 1/8), L1 their chunks (1 m, at 1/64).
## Generate plans the world. The wheel zooms toward the mouse within the level's range (RANGE times
## its STANDARD zoom); a notch past the top plays a transition down a level, into more detail, and
## one past the bottom a transition up. Regions round the view are refined from the world, and
## chunks from their region, on worker threads, nearest first (WorldRegions, WorldTerrainChunks):
## planned, then drawn, chunks then objects planned and drawn. Coarser levels stay drawn beneath, so
## what isn't made yet shows its parent. Far regions and chunks free their nodes and keep their plans.
## A left click shows the cell under it at the level shown.

const WORLD := "res://13. World Generator/defs/lands/world.tres"
const CHUNK_SIZES: Array[int] = [32, 64, 128]
const WATER_NAMES: Array[String] = ["The world's", "Lake", "River", "Coast", "River to the sea"]
## Child cells per parent cell side: L3 to L2 and L2 to L1.
const ZOOM: int = 8
## Each level's standard zoom, L3, L2, L1: a cell of that level CELL px on screen.
const STANDARD: Array[float] = [0.25, 2.0, 32.0]
## A level's zoom range, as shares of its standard zoom.
const RANGE := Vector2(0.7, 1.5)
const LEVEL_NAMES: Array[String] = ["L3", "L2", "L1"]
## Metres a cell, by level.
const METRES: Array[int] = [64, 8, 1]
## Each wheel notch multiplies or divides the zoom by this.
const WHEEL_STEP: float = 1.15
## Seconds a region or chunk takes to fade in.
const FADE: float = 0.35
## Seconds a transition between levels takes.
const TRANSITION: float = 0.45
## Worker tasks at once.
const MAX_JOBS: int = 3
## Chunks made round the view, ahead of panning.
const RING: int = 1
## Drawn chunks further than this many chunks outside the view free their nodes.
const KEEP: int = 3
## L3 cells round the view whose regions are made too.
const REGION_MARGIN: int = 2
## Ticks a new level is run on the worker before it is shown, so everything is born and drawn.
const SETTLE: int = 3
## Deposit tint by key.
const DEPOSIT_TINTS := {&"iron": Color(0.75, 0.35, 0.2), &"coal": Color(0.1, 0.1, 0.1), &"copper": Color(0.85, 0.5, 0.15),
	&"gold": Color(1.0, 0.85, 0.1), &"clay": Color(0.7, 0.45, 0.35)}
## Zone tint, most specific zone first: [zone, colour].
const TINTS := [
	[WorldNodeSpawnDef.Zone.SHALLOW, Color(0.3, 0.9, 1.0)], [WorldNodeSpawnDef.Zone.SHORE, Color(1.0, 0.9, 0.3)],
	[WorldNodeSpawnDef.Zone.ROCK_INNER, Color(0.25, 0.25, 0.3)], [WorldNodeSpawnDef.Zone.ROCK, Color(0.6, 0.6, 0.65)],
	[WorldNodeSpawnDef.Zone.DEEP_FOREST, Color(0.0, 0.3, 0.1)], [WorldNodeSpawnDef.Zone.FOREST_EDGE, Color(0.6, 0.9, 0.3)],
	[WorldNodeSpawnDef.Zone.FOREST, Color(0.2, 0.6, 0.2)],
]

@export var catalog: EcsTownCatalog
@export var entity_catalog: EcsEntityCatalog

@onready var _world_root: Node2D = $World
@onready var _camera: Camera2D = $Camera2D
@onready var _ui: Control = $UI/Root

var _panel: PanelContainer
var _chunk_size: OptionButton
var _water: OptionButton
var _seed: SpinBox
var _generate_button: Button
## What the world job is doing, shown as a bar and a line under Generate.
var _progress := WorldProgress.new()
var _progress_bar: ProgressBar
var _progress_label: Label
var _info: Label
var _detail_panel: PanelContainer
var _detail: Label
## The clicked cell's outline, and the cell: {level: 0 L3, 1 L2, 2 L1, cell}, or {}.
var _marker: Line2D
var _picked: Dictionary = {}
var _zones_on: bool = false
var _nodes_on: bool = true
var _roofs_on: bool = false
## The world shown: {root, world, scheduler, tile_sync, grid, def, plan, seed, problems, zones}.
var _world: Dictionary = {}
## Counts worlds made, so a job for an old one is thrown away.
var _generation: int = 0
## One layer per level, coarsest first; each region's and chunk's root goes under its level's.
var _layers: Array[Node2D] = []
var _regions: WorldRegions
var _region_def: WorldLandDef
var _chunks: WorldTerrainChunks
var _chunk_def: WorldLandDef
## The level shown: 0 L3, 1 L2, 2 L1.
var _level: int = 0
## The transition running, and the zoom and camera position it ends at.
var _transition: Tween
var _target_zoom: float = 1.0
var _target_position: Vector2
## Worker tasks: id -> job {kind, generation, region or chunk, stage, work result}.
var _jobs: Dictionary = {}

func _ready() -> void:
	catalog.number()
	# Builds the catalog's lookup here, so the workers only ever read it.
	entity_catalog.has_def(&"tree")
	# Texture arrays touch the renderer, so they're made here and workers only read them.
	for level in [1, 2, 3]:
		catalog.grounds(level)
	catalog.surfaces()
	catalog.pieces()
	_build_panel()
	_build_detail_panel()
	for level in STANDARD.size():
		var layer := Node2D.new()
		layer.name = LEVEL_NAMES[level]
		layer.modulate.a = 1.0 if level == 0 else 0.0
		_world_root.add_child(layer)
		_layers.append(layer)
	_marker = Line2D.new()
	_marker.closed = true
	_marker.default_color = Color(1.0, 0.85, 0.2)
	_marker.z_index = 30
	_marker.visible = false
	_world_root.add_child(_marker)
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
	if _world.is_empty():
		return
	_stream()
	_report()
	if _marker.visible:
		_marker.width = 3.0 / _camera.zoom.x

func _physics_process(delta: float) -> void:
	for level in _levels():
		(level["scheduler"] as EcsScheduler).run_all(level["world"], delta)

## Every level drawn: the world, drawn regions, drawn chunks.
func _levels() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _world.is_empty():
		return out
	out.append(_world)
	for store: Dictionary in [_regions.regions, _chunks.chunks]:
		for at: Vector2i in store:
			if store[at].has("level"):
				out.append(store[at]["level"])
	return out

## Starts the next region and chunk jobs for the view, and offers far ones up to free: regions from
## L2 down, their chunks at L1, each only once its region is planned.
func _stream() -> void:
	var around := _view_cells(0).grow(REGION_MARGIN)
	if _level >= 1:
		while _jobs.size() < MAX_JOBS:
			var next := _regions.next_job(around)
			if next.is_empty():
				break
			_start_region(next["region"], next["stage"])
	for at in _regions.far(around, 1):
		_undraw(_regions.regions[at])
	var view := _view_cells(2)
	if _level == 2:
		var ready := func(at: Vector2i) -> bool: return _regions.planned(_region_of_chunk(at))
		while _jobs.size() < MAX_JOBS:
			var next := _chunks.next_job(view, RING, ready)
			if next.is_empty():
				break
			_start_chunk(next["chunk"], next["stage"])
	for at in _chunks.far(view, KEEP):
		_undraw(_chunks.chunks[at])

## The wheel zooms by a factor toward the mouse within the level's range; past it, a transition.
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
	if _transitioning() or _world.is_empty():
		return
	var at := get_global_mouse_position()
	var zoom := _camera.zoom.x * step
	if zoom > STANDARD[_level] * RANGE.y and _level < STANDARD.size() - 1:
		_go_to_level(_level + 1, at)
	elif zoom < STANDARD[_level] * RANGE.x and _level > 0:
		_go_to_level(_level - 1, at)
	else:
		_zoom_at(at, zoom)

## A left click on the map picks the cell under it.
func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or _world.is_empty():
		return
	if event.button_index == MOUSE_BUTTON_LEFT and not _transitioning():
		_pick(get_global_mouse_position())

## Sets the zoom within the level's range, keeping world point `at` where it is on screen (or on
## screen point `screen` when given).
func _zoom_at(at: Vector2, zoom: float, screen: Variant = null) -> void:
	if screen == null:
		screen = get_viewport().get_canvas_transform() * at
	if not _transitioning():
		zoom = clampf(zoom, STANDARD[_level] * RANGE.x, STANDARD[_level] * RANGE.y)
	zoom = clampf(zoom, _camera.min_zoom, _camera.max_zoom)
	_camera.zoom = Vector2(zoom, zoom)
	_camera.position = at - ((screen as Vector2) - get_viewport_rect().size * 0.5) / zoom

## Plays the transition to `level`: the zoom eases to its standard with world point `at` held still
## on screen, the finer of the two levels fades (the coarser stays beneath), and input waits.
## The new level's regions or chunks are asked for from the start, for the view it ends on.
func _go_to_level(level: int, at: Vector2) -> void:
	var from := _camera.zoom.x
	var screen := get_viewport().get_canvas_transform() * at
	var finer := maxi(level, _level)
	_target_zoom = STANDARD[level]
	_target_position = at - (screen - get_viewport_rect().size * 0.5) / _target_zoom
	_level = level
	_camera.manual_control = false
	_camera.is_panning = false
	_transition = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_transition.tween_method(func(t: float) -> void: _zoom_at(at, from * pow(_target_zoom / from, t), screen), 0.0, 1.0, TRANSITION)
	_transition.tween_property(_layers[finer], "modulate:a", 1.0 if level == finer else 0.0, TRANSITION)
	_transition.chain().tween_callback(func() -> void:
		_camera.manual_control = true
		_camera.zoom = Vector2(_target_zoom, _target_zoom)
		_camera.position = _target_position)
	_show_layers()
	_stream()

func _transitioning() -> bool:
	return _transition != null and _transition.is_running()

## What the camera shows, or will once a transition ends, in world px.
func _view_rect() -> Rect2:
	var zoom := _target_zoom if _transitioning() else _camera.zoom.x
	var centre := _target_position if _transitioning() else _camera.get_screen_center_position()
	var half := get_viewport_rect().size * 0.5 / zoom
	return Rect2(centre - half, half * 2.0)

## The view in `level`'s cells.
func _view_cells(level: int) -> Rect2i:
	var view := _view_rect()
	var from := (view.position / _cell_px(level)).floor()
	var to := (view.end / _cell_px(level)).ceil()
	return Rect2i(Vector2i(from), Vector2i(to - from))

## World px a cell of `level` spans.
func _cell_px(level: int) -> float:
	return EcsTownGrid.CELL / pow(ZOOM, level)

## The region a chunk lies in.
func _region_of_chunk(at: Vector2i) -> Vector2i:
	return Vector2i((Vector2(at * _chunks.size) / Vector2(_region_def.size * ZOOM)).floor())

func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"DockPanel"
	_panel.position = Vector2(12, 12)
	_panel.custom_minimum_size = Vector2(300, 0)
	_ui.add_child(_panel)
	var box := VBoxContainer.new()
	_panel.add_child(box)
	var title := Label.new()
	title.text = "World terrain"
	title.theme_type_variation = &"DockTitle"
	box.add_child(title)
	_chunk_size = _option(box, "L1 chunk", CHUNK_SIZES.map(func(n: int) -> String: return "%d×%d cells" % [n, n]))
	_chunk_size.select(0)
	_chunk_size.item_selected.connect(func(_k: int) -> void: _reset_chunks())
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

## Picks the cell at `at` (world position) at the level shown, or the nearest coarser level where
## that one isn't made there yet.
func _pick(at: Vector2) -> void:
	var level := _level
	if level == 2 and not (_chunks.chunks.get(_chunks.chunk_at(_cell_at(at, 2)), {}) as Dictionary).get("drawn", false):
		level = 1
	if level == 1 and not _regions.planned(_regions.region_at(_cell_at(at, 0))):
		level = 0
	var cell := _cell_at(at, level)
	if not Rect2i(Vector2i.ZERO, (_world["def"] as WorldLandDef).size * int(pow(ZOOM, level))).has_point(cell):
		return
	_picked = {"level": level, "cell": cell}
	var size := _cell_px(level)
	var corner := Vector2(cell) * size
	_marker.points = PackedVector2Array([corner, corner + Vector2(size, 0), corner + Vector2(size, size), corner + Vector2(0, size)])
	_marker.visible = true
	_detail_panel.visible = true
	_describe()

func _cell_at(at: Vector2, level: int) -> Vector2i:
	return Vector2i((at / _cell_px(level)).floor())

## The picked cell's details, refreshed as its region or chunk is made.
func _describe() -> void:
	if _picked.is_empty():
		return
	var cell: Vector2i = _picked["cell"]
	var lines := PackedStringArray()
	var world := _world["def"] as WorldLandDef
	var world_plan := _world["plan"] as Dictionary
	match int(_picked["level"]):
		0:
			var i := cell.y * world.size.x + cell.x
			var kind: int = (world_plan["kinds"] as PackedByteArray)[i]
			lines.append("L3 cell %s, 64 m a side" % cell)
			lines.append("Ground: %s%s" % [WorldTerrainGenerator.TERRAIN_KEYS[kind],
				", river" if (world_plan["river"] as PackedByteArray)[i] != 0 else (", sea" if kind == WorldTerrainGenerator.WATER else "")])
			lines.append("Zones: %s" % _zone_names((world_plan["zones"] as PackedByteArray)[i]))
			lines.append("Walk cost: %s" % _walk_cost(kind))
			lines.append("In region %s; holds L2 cells %s to %s" % [_regions.region_at(cell), cell * ZOOM, cell * ZOOM + Vector2i(ZOOM - 1, ZOOM - 1)])
		1:
			var at := _regions.region_at(cell / ZOOM)
			var local := cell - at * _region_def.size
			var plan: Dictionary = _regions.regions[at]["plan"]
			var i := local.y * _region_def.size.x + local.x
			var kind: int = (plan["kinds"] as PackedByteArray)[i]
			lines.append("L2 cell %s, 8 m a side" % cell)
			lines.append("Region %s, cell %s in it" % [at, local])
			lines.append("Ground: %s%s" % [WorldTerrainGenerator.TERRAIN_KEYS[kind],
				", river" if (plan["river"] as PackedByteArray)[i] != 0 else (", sea" if kind == WorldTerrainGenerator.WATER else "")])
			lines.append("Zones: %s" % _zone_names((plan["zones"] as PackedByteArray)[i]))
			lines.append("Walk cost: %s" % _walk_cost(kind))
			var ids := plan["deposits"]["ids"] as PackedByteArray
			if not ids.is_empty() and ids[i] != 0:
				lines.append("Deposit: %s" % plan["deposits"]["keys"][ids[i] - 1])
			lines.append("In L3 cell %s: %s" % [cell / ZOOM, _world_kind(cell / ZOOM)])
		2:
			var at := _chunks.chunk_at(cell)
			var chunk: Dictionary = _chunks.chunks.get(at, {})
			var local := cell - at * _chunks.size
			var parent := cell / ZOOM
			lines.append("L1 cell %s, 1 m a side" % cell)
			lines.append("Chunk %s, cell %s in it" % [at, local])
			if chunk.has("terrain"):
				var outer := _chunks.size + 2
				var kind: int = (chunk["terrain"]["kinds"] as PackedByteArray)[(local.y + 1) * outer + local.x + 1]
				lines.append("Ground: %s%s" % [WorldTerrainGenerator.TERRAIN_KEYS[kind],
					", river" if (chunk["terrain"]["river"] as PackedByteArray)[(local.y + 1) * outer + local.x + 1] != 0 else ""])
				lines.append("Zones: %s" % _zone_names((chunk["terrain"]["zones"] as PackedByteArray)[local.y * _chunks.size + local.x]))
				lines.append("Walk cost: %s" % _walk_cost(kind))
			lines.append("Object: %s" % _object_at(chunk, local))
			var region := _regions.region_at(parent / ZOOM)
			if _regions.planned(region):
				var plan: Dictionary = _regions.regions[region]["plan"]
				var p := parent - region * _region_def.size
				lines.append("In L2 cell %s: %s" % [parent, WorldTerrainGenerator.TERRAIN_KEYS[(plan["kinds"] as PackedByteArray)[p.y * _region_def.size.x + p.x]]])
			var made := PackedStringArray()
			for step: Array in [["terrain", chunk.has("terrain")], ["drawn", chunk.get("drawn", false)],
					["objects", chunk.has("nodes")], ["objects drawn", chunk.get("objects_drawn", false)]]:
				if step[1]:
					made.append(step[0])
			lines.append("Chunk made: %s" % (", ".join(made) if not made.is_empty() else "nothing yet"))
	_detail.text = "\n".join(lines)

func _world_kind(cell: Vector2i) -> String:
	var world := _world["def"] as WorldLandDef
	return WorldTerrainGenerator.TERRAIN_KEYS[(_world["plan"]["kinds"] as PackedByteArray)[cell.y * world.size.x + cell.x]]

func _zone_names(bits: int) -> String:
	var names := PackedStringArray()
	for zone in WorldNodeSpawnDef.Zone.size():
		if bits & (1 << zone):
			names.append(String(WorldNodeSpawnDef.Zone.keys()[zone]).to_lower().replace("_", " "))
	return ", ".join(names) if not names.is_empty() else "none"

func _walk_cost(kind: int) -> String:
	var cost := catalog.terrain(catalog.terrain_id(WorldTerrainGenerator.TERRAIN_KEYS[kind])).walk_cost
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

## Plans the world from the inputs, and builds its L3 level, on a worker thread.
func _generate() -> void:
	for job: Dictionary in _jobs.values():
		if job["kind"] == &"world":
			return
	var def := (load(WORLD) as WorldLandDef).duplicate() as WorldLandDef
	if _water.selected > 0 and _water.selected - 1 != def.water:
		def.water = _water.selected - 1
		def.water_share = 0.03 if def.water == WorldLandDef.Water.RIVER else (0.18 if def.water == WorldLandDef.Water.RIVER_TO_SEA else 0.12)
	var rng_seed := int(_seed.value)
	_generation += 1
	_generate_button.disabled = true
	var progress := WorldProgress.new()
	_progress = progress
	_start({"kind": &"world"}, func() -> Dictionary:
		progress.within(0.0, 0.3)
		var plan := WorldTerrainGenerator.plan(def, rng_seed, catalog, entity_catalog, progress)
		progress.within(0.3, 1.0)
		progress.report("Building the world's tiles")
		var level := _make_level(def.size, plan["commands"], Vector2.ZERO, 1.0, false, 0)
		progress.report("Checking the terrain", 0.9)
		level.merge({"def": def, "plan": plan, "seed": rng_seed, "problems": WorldTerrainCheck.problems(def, plan),
			"tint": _tint(def.size, plan["zones"])})
		progress.report("Showing the world", 1.0)
		return level)

## Starts region `at`'s `stage` on a worker: its plan, an L3 window refined 8×, or its drawing.
func _start_region(at: Vector2i, stage: int) -> void:
	if not _regions.regions.has(at):
		_regions.regions[at] = {}
	var region: Dictionary = _regions.regions[at]
	var def := _region_def
	var job := {"kind": &"region", "region": at, "stage": stage}
	region["busy"] = true
	match stage:
		WorldRegions.Stage.PLAN:
			var parent: Dictionary = _world["plan"]
			var world: WorldLandDef = _world["def"]
			var rng_seed: int = _world["seed"]
			var origin := at * _regions.window
			_start(job, func() -> Dictionary:
				var plan := WorldTerrainGenerator.refine(parent, world, def, origin, ZOOM, rng_seed, catalog, entity_catalog, 1)
				return {"plan": plan, "shares": WorldTerrainGenerator.blend_shares(plan, def)})
		WorldRegions.Stage.DRAW:
			var plan: Dictionary = region["plan"]
			var outer := def.size + Vector2i(2, 2)
			# Its border cells are its neighbours', drawn the same by both.
			var origin := Vector2(at * _regions.window) * _cell_px(0) - Vector2.ONE * _cell_px(1)
			_start(job, func() -> Dictionary:
				var commands := WorldTerrainGenerator.terrain_commands(plan["outer_kinds"], outer, Vector2i.ZERO, catalog)
				var level := _make_level(outer, commands, origin, 1.0 / ZOOM, true, 1)
				level["tint"] = _tint(def.size, plan["zones"])
				level["deposit_tint"] = _deposit_tint(def, plan["deposits"])
				return level)

## Starts chunk `at`'s `stage` on a worker; its terrain is refined from its region.
func _start_chunk(at: Vector2i, stage: int) -> void:
	if not _chunks.chunks.has(at):
		_chunks.chunks[at] = {}
	var chunk: Dictionary = _chunks.chunks[at]
	var size := _chunks.size
	var region_at := _region_of_chunk(at)
	var rng_seed := hash([_world["seed"], region_at])
	var job := {"kind": &"chunk", "chunk": at, "stage": stage}
	chunk["busy"] = true
	match stage:
		WorldTerrainChunks.Stage.TERRAIN:
			var region: Dictionary = _regions.regions[region_at]
			var parent: Dictionary = region["plan"]
			var shares: Array = region["shares"]
			var def := _region_def
			var shore := _chunk_def.shore_width
			var local := at * size - region_at * _region_def.size * ZOOM
			_start(job, func() -> Dictionary:
				return WorldTerrainGenerator.refine_terrain(parent, def, Vector2i(size, size), shore, local, ZOOM, rng_seed, 1, shares))
		WorldTerrainChunks.Stage.DRAW_TERRAIN, WorldTerrainChunks.Stage.DRAW_OBJECTS:
			var kinds: PackedByteArray = chunk["terrain"]["kinds"]
			var nodes: Array = chunk["nodes"] if stage == WorldTerrainChunks.Stage.DRAW_OBJECTS else []
			var origin := Vector2(at * size - Vector2i.ONE) * _cell_px(2)
			_start(job, func() -> Dictionary:
				var outer := Vector2i(size, size) + Vector2i(2, 2)
				var commands := WorldTerrainGenerator.terrain_commands(kinds, outer, Vector2i.ZERO, catalog)
				# A chunk's cells sit one in from its border, which is its neighbours'.
				for node: Dictionary in nodes:
					commands.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT,
						(node["cell"] as Vector2i) + Vector2i.ONE, node["blueprint"], 0))
				return _make_level(outer, commands, origin, 1.0 / (ZOOM * ZOOM), true, 2))
		WorldTerrainChunks.Stage.OBJECTS:
			var zones: PackedByteArray = chunk["terrain"]["zones"]
			var deposits: Dictionary = chunk["terrain"]["deposits"]
			var def := _chunk_def
			_start(job, func() -> Dictionary:
				return {"nodes": WorldTerrainGenerator.refine_nodes(def, zones, rng_seed, at, entity_catalog, PackedByteArray(), deposits)})

func _start(job: Dictionary, work: Callable) -> void:
	job["generation"] = _generation
	var task := WorkerThreadPool.add_task(func() -> void: job["result"] = work.call(), false, "world terrain")
	_jobs[task] = job

## A world of `size` through module 10's pipeline, run until settled, under a root placed at `at`
## and scaled by `scale`, built off the scene tree, for map level `level`. `trim` erases the outer
## ring of roof tiles, which show cells past the edge. Runs on a worker.
func _make_level(size: Vector2i, commands: Array[EcsBuildCommand], at: Vector2, scale: float, trim: bool, level: int) -> Dictionary:
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
	tile_sync.level = 3 - level
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
	return {"root": root, "world": world, "scheduler": scheduler, "tile_sync": tile_sync, "grid": grid, "map_level": level,
		"build_usec": Time.get_ticks_usec() - started}

## What a worker made goes into the scene, unless it was for a world since replaced.
func _arrived(job: Dictionary) -> void:
	var result: Dictionary = job["result"]
	if job["kind"] == &"world":
		_generate_button.disabled = false
		_show_world(result)
		return
	if job["generation"] != _generation:
		if result.has("root"):
			(result["root"] as Node2D).free()
		return
	if job["kind"] == &"region":
		var region: Dictionary = _regions.regions[job["region"]]
		region["busy"] = false
		if job["stage"] == WorldRegions.Stage.PLAN:
			region.merge(result)
		else:
			_add_sprite(result, result["tint"], 20, &"zones", Vector2.ONE)
			_add_sprite(result, result["deposit_tint"], 21, &"deposits", Vector2.ONE)
			_put(region, result, 1)
		return
	var chunk: Dictionary = _chunks.chunks[job["chunk"]]
	chunk["busy"] = false
	match job["stage"]:
		WorldTerrainChunks.Stage.TERRAIN:
			chunk["terrain"] = result
		WorldTerrainChunks.Stage.DRAW_TERRAIN, WorldTerrainChunks.Stage.DRAW_OBJECTS:
			chunk["objects_drawn"] = job["stage"] == WorldTerrainChunks.Stage.DRAW_OBJECTS
			_put(chunk, result, 2)
		WorldTerrainChunks.Stage.OBJECTS:
			chunk["nodes"] = result["nodes"]

## Puts a drawn region or chunk under its level's layer, fading in over what it replaces, which goes
## once it is covered.
func _put(part: Dictionary, level: Dictionary, layer: int) -> void:
	var old: Node2D = part["level"]["root"] if part.has("level") else null
	part["level"] = level
	part["drawn"] = true
	var root := level["root"] as Node2D
	root.modulate.a = 0.0
	_layers[layer].add_child(root)
	var tween := create_tween()
	tween.tween_property(root, "modulate:a", 1.0, FADE)
	if old != null:
		tween.tween_callback(old.queue_free)
	_show_layers()

## A tint image as a sprite on `level`'s root, a cell a pixel, `offset` cells in (past a border).
func _add_sprite(level: Dictionary, image: Image, z: int, key: StringName, offset: Vector2) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(image)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.centered = false
	sprite.z_index = z
	sprite.scale = Vector2(EcsTownGrid.CELL, EcsTownGrid.CELL)
	sprite.position = offset * EcsTownGrid.CELL
	(level["root"] as Node2D).add_child(sprite)
	level[key] = sprite

## Frees a far region's or chunk's nodes and world; its plans stay, so it is only redrawn.
func _undraw(part: Dictionary) -> void:
	(part["level"]["root"] as Node2D).queue_free()
	part.erase("level")
	part["drawn"] = false
	part["objects_drawn"] = false

func _show_world(level: Dictionary) -> void:
	_generation += 1
	if not _world.is_empty():
		(_world["root"] as Node2D).queue_free()
	for layer in _layers:
		for child in layer.get_children():
			child.queue_free()
	_add_sprite(level, level["tint"], 20, &"zones", Vector2.ZERO)
	_world = level
	_layers[0].add_child(level["root"])
	var def := level["def"] as WorldLandDef
	_region_def = def.child
	_regions = WorldRegions.new(def.size, _region_def.size / ZOOM)
	_reset_chunks()
	_level = 0
	for k in _layers.size():
		_layers[k].modulate.a = 1.0 if k == 0 else 0.0
	_camera.zoom = Vector2(STANDARD[0], STANDARD[0])
	_camera.position = Vector2(def.size) * _cell_px(0) * 0.5
	_show_layers()

## Drops every chunk and starts L1 afresh, for a new world or chunk size.
func _reset_chunks() -> void:
	if _world.is_empty():
		return
	if _chunks != null:
		for at: Vector2i in _chunks.chunks:
			if _chunks.chunks[at].has("level"):
				(_chunks.chunks[at]["level"]["root"] as Node2D).queue_free()
	_chunks = WorldTerrainChunks.new((_world["def"] as WorldLandDef).size * ZOOM, ZOOM, CHUNK_SIZES[_chunk_size.selected])
	_chunk_def = _region_def.child.duplicate() as WorldLandDef
	_chunk_def.size = Vector2i(_chunks.size, _chunks.size)
	_picked = {}
	_marker.visible = false
	_detail_panel.visible = false
	for job: Dictionary in _jobs.values():
		if job["kind"] == &"chunk":
			job["generation"] = -1

## The regions' deposits as an image, a cell a pixel, each tinted by its key.
func _deposit_tint(def: WorldLandDef, deposits: Dictionary) -> Image:
	var image := Image.create(def.size.x, def.size.y, false, Image.FORMAT_RGBA8)
	var ids := deposits["ids"] as PackedByteArray
	var keys := deposits["keys"] as Array
	for i in ids.size():
		if ids[i] != 0:
			var tint: Color = DEPOSIT_TINTS.get(keys[ids[i] - 1], Color.MAGENTA)
			image.set_pixel(i % def.size.x, i / def.size.x, Color(tint, 0.7))
	return image

## The bar and line under Generate: the world job's stage while it runs, else how many regions (L2)
## or chunks (L1) in view are made; hidden when nothing is under way.
func _show_progress() -> void:
	var stage := ""
	var done := 0.0
	var working := false
	for job: Dictionary in _jobs.values():
		working = working or job["kind"] == &"world"
	if working:
		var read := _progress.read()
		stage = read[0] if read[0] != "" else "Starting"
		done = read[1]
	elif not _world.is_empty() and _level >= 1:
		var store: Dictionary = _regions.regions if _level == 1 else _chunks.chunks
		var visible: Array[Vector2i] = _regions.around(_view_cells(0)) if _level == 1 else _chunks.around(_view_cells(2), 0)
		var key := "drawn" if _level == 1 else "objects_drawn"
		var made := 0
		for at in visible:
			made += 1 if (store.get(at, {}) as Dictionary).get(key, false) else 0
		if made < visible.size():
			stage = "Streaming %s into view: %d of %d %s made" % [LEVEL_NAMES[_level], made, visible.size(),
				"regions" if _level == 1 else "chunks"]
			done = float(made) / visible.size()
	_progress_label.visible = stage != ""
	_progress_bar.visible = stage != ""
	_progress_label.text = stage
	_progress_bar.value = done * 100.0

## The nodes, roofs and tint toggles on every level drawn; tints only on the level shown.
func _show_layers() -> void:
	for level in _levels():
		var sync := level["tile_sync"] as EcsTileSyncSystem
		sync.furniture_layer().visible = _nodes_on
		sync.attachment_layer().visible = _nodes_on
		sync.roofs_visible = _roofs_on
		var shown: bool = level["map_level"] == _level
		if level.has("zones"):
			(level["zones"] as Sprite2D).visible = _zones_on and shown
		if level.has("deposits"):
			(level["deposits"] as Sprite2D).visible = shown

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

func _report() -> void:
	var def := _world["def"] as WorldLandDef
	var problems := _world["problems"] as Array[String]
	var regions := _regions.tally()
	var chunks := _chunks.tally()
	var lines := PackedStringArray([
		"L3 world %d×%d at 64 m a cell, %s, seed %d" % [def.size.x, def.size.y, WATER_NAMES[def.water + 1].to_lower(), _world["seed"]],
		"Sound" if problems.is_empty() else "Problems: " + "; ".join(problems),
		"%s, %d m a cell: zoom ×%.2f (×%.2f to ×%.2f)%s" % [LEVEL_NAMES[_level], METRES[_level], _camera.zoom.x,
			STANDARD[_level] * RANGE.x, STANDARD[_level] * RANGE.y, ", moving" if _transitioning() else ""],
		"Regions of %d×%d L2 cells, %d×%d across: planned %d, drawn %d" % [_region_def.size.x, _region_def.size.y,
			_regions.count.x, _regions.count.y, regions[0], regions[1]],
		"L1 chunks of %d×%d: terrain planned %d, drawn %d; objects planned %d, drawn %d" % [_chunks.size, _chunks.size,
			chunks[0], chunks[1], chunks[2], chunks[3]],
		"Worker jobs running %d" % _jobs.size(),
	])
	_info.text = "\n".join(lines)
	_describe()
