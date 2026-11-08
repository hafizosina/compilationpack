extends Node2D

## The terrain generator's viewer: an L2 region and, zoomed in, its L1 ground in chunks.
## Generate plans the region (8 m a cell). The wheel zooms toward the mouse; past a zoom where L1
## cells are big enough to see (1 m a cell, drawn at 1/8 over the region), the chunks in view and a
## ring round them are made, each in turn: terrain planned, terrain drawn, objects planned, objects
## drawn (EcsTerrainChunks says which). Planning and building a chunk's world run on worker
## threads, off the scene tree: drawing objects rebuilds the chunk with them and swaps it in over
## the terrain-only one, so the main thread only ever adds a finished chunk. Made chunks stay in
## memory; far ones free their nodes and keep their plans. Zooming out fades L1 away. A left click
## on the map outlines that cell, L1's where L1 is drawn, else L2's, and shows its details.

const DEFS := "res://12. Settlement Generator/defs/settlements/"
## The def L1 chunks take their shore and nodes from.
const L1_DEF: StringName = &"town"
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
var _water: OptionButton
var _seed: SpinBox
var _generate_button: Button
var _info: Label
var _detail_panel: PanelContainer
var _detail: Label
## The clicked cell's outline, and the cell: {level: 1 or 2, cell}, or {}.
var _marker: Line2D
var _picked: Dictionary = {}
var _zones_on: bool = false
var _nodes_on: bool = true
## The region shown: {root, world, scheduler, tile_sync, zones, def, plan, shares, seed, problems}.
var _region: Dictionary = {}
## Counts regions made, so a chunk job for an old one is thrown away.
var _generation: int = 0
## L1: the layer every chunk's root goes under, the chunks, and their L1 def.
var _l1: Node2D
var _chunks: EcsTerrainChunks
var _chunk_def: EcsSettlementDef
var _in_l1: bool = false
var _l1_tween: Tween
## Worker tasks: id -> job {kind, generation, chunk, stage, work result}.
var _jobs: Dictionary = {}

func _ready() -> void:
	catalog.number()
	# Builds the catalog's lookup here, so the workers only ever read it.
	entity_catalog.has_def(&"tree")
	_build_panel()
	_build_detail_panel()
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

## A left click on the map picks the cell under it.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not _region.is_empty():
		_pick(get_global_mouse_position())

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
	var nodes := CheckBox.new()
	nodes.text = "Nodes"
	nodes.button_pressed = true
	nodes.toggled.connect(func(on: bool) -> void: _nodes_on = on; _show_layers())
	box.add_child(nodes)
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
	var region := _region["def"] as EcsSettlementDef
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
	var region := _region["def"] as EcsSettlementDef
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
		lines.append("In L2 cell %s: %s" % [parent, EcsTerrainGenerator.TERRAIN_KEYS[(plan["kinds"] as PackedByteArray)[parent.y * region.size.x + parent.x]]])
		var made := PackedStringArray()
		for step: Array in [["terrain", chunk.has("terrain")], ["drawn", chunk.get("drawn", false)],
				["objects", chunk.has("nodes")], ["objects drawn", chunk.get("objects_drawn", false)]]:
			if step[1]:
				made.append(step[0])
		lines.append("Chunk made: %s" % (", ".join(made) if not made.is_empty() else "nothing yet"))
	_detail.text = "\n".join(lines)

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
	var def := (load(DEFS + "region.tres") as EcsSettlementDef).duplicate() as EcsSettlementDef
	if _water.selected > 0 and _water.selected - 1 != def.water:
		def.water = _water.selected - 1
		def.water_share = 0.03 if def.water == EcsSettlementDef.Water.RIVER else (0.18 if def.water == EcsSettlementDef.Water.RIVER_TO_SEA else 0.12)
	var rng_seed := int(_seed.value)
	_generation += 1
	_generate_button.disabled = true
	_start({"kind": &"region"}, func() -> Dictionary:
		var plan := EcsTerrainGenerator.plan(def, rng_seed, catalog, entity_catalog)
		var level := _make_level(def.size, plan["commands"], Vector2.ZERO, 1.0, false)
		level.merge({"def": def, "plan": plan, "seed": rng_seed, "problems": EcsTerrainCheck.problems(def, plan),
			"shares": EcsTerrainGenerator.blend_shares(plan, def), "tint": _tint(def.size, plan["zones"])})
		return level)

## Starts chunk `at`'s `stage` on a worker.
func _start_chunk(at: Vector2i, stage: int) -> void:
	if not _chunks.chunks.has(at):
		_chunks.chunks[at] = {}
	var chunk: Dictionary = _chunks.chunks[at]
	var size := _chunks.size
	var job := {"kind": &"chunk", "chunk": at, "stage": stage}
	match stage:
		EcsTerrainChunks.Stage.TERRAIN:
			var parent: Dictionary = _region["plan"]
			var region: EcsSettlementDef = _region["def"]
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
			var origin := Vector2(at * size - Vector2i.ONE) * EcsTownGrid.CELL / ZOOM
			chunk["busy"] = true
			_start(job, func() -> Dictionary:
				var outer := Vector2i(size, size) + Vector2i(2, 2)
				var commands := EcsTerrainGenerator.terrain_commands(kinds, outer, Vector2i.ZERO, catalog)
				# A chunk's cells sit one in from its border, which is its neighbours'.
				for node: Dictionary in nodes:
					commands.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT,
						(node["cell"] as Vector2i) + Vector2i.ONE, node["blueprint"], 0))
				return _make_level(outer, commands, origin, 1.0 / ZOOM, true))
		EcsTerrainChunks.Stage.OBJECTS:
			var zones: PackedByteArray = chunk["terrain"]["zones"]
			var def := _chunk_def
			var rng_seed: int = _region["seed"]
			chunk["busy"] = true
			_start(job, func() -> Dictionary:
				return {"nodes": EcsTerrainGenerator.refine_nodes(def, zones, rng_seed, at, entity_catalog)})

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
	var scheduler := EcsScheduler.new()
	scheduler \
		.add(EcsLifecycleSystem.new(EcsEntityManager.new(entities), entity_catalog)) \
		.add(EcsBuildCommandSystem.new(catalog, entity_catalog)) \
		.add(EcsTownNavSystem.new(catalog)) \
		.add(tile_sync)
	for tick in SETTLE:
		scheduler.run_all(world, 1.0 / 60.0)
	# Every chunk's ground reaches half a cell into its neighbours, so pieces draw above all ground.
	for layer: TileMapLayer in [tile_sync.furniture_layer(), tile_sync.wall_layer(), tile_sync.attachment_layer()]:
		layer.z_index = 1
	if trim:
		for layer in tile_sync.terrain_layers() + tile_sync.floor_layers():
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
	var at: Vector2i = job["chunk"]
	var chunk: Dictionary = _chunks.chunks[at]
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
	_region = level
	_world_root.add_child(level["root"])
	_reset_l1()
	_frame()
	_show_layers()

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
	_chunks = EcsTerrainChunks.new((_region["def"] as EcsSettlementDef).size, ZOOM, CHUNK_SIZES[_chunk_size.selected])
	_chunk_def = (load(DEFS + "%s.tres" % L1_DEF) as EcsSettlementDef).duplicate() as EcsSettlementDef
	_chunk_def.size = Vector2i(_chunks.size, _chunks.size)
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
	var span := Vector2((_region["def"] as EcsSettlementDef).size * EcsTownGrid.CELL)
	var view := get_viewport_rect().size
	var room := Vector2(view.x - left, view.y)
	var zoom := minf(room.x / span.x, room.y / span.y)
	_camera.zoom = Vector2(zoom, zoom)
	_camera.position = span * 0.5 - Vector2(left * 0.5 / zoom, 0)

func _report() -> void:
	var region := _region["def"] as EcsSettlementDef
	var problems := _region["problems"] as Array[String]
	var tally := _chunks.tally()
	var lines := PackedStringArray([
		"L2 region %d×%d at 8 m a cell, %s, seed %d" % [region.size.x, region.size.y,
			WATER_NAMES[region.water + 1].to_lower(), _region["seed"]],
		"Sound" if problems.is_empty() else "Problems: " + "; ".join(problems),
		"Zoom ×%.2f: %s" % [_camera.zoom.x, "L1, 1 m a cell" if _in_l1 else "L2 (L1 from ×%.2f)" % L1_ZOOM],
		"L1 chunks of %d×%d, %d×%d across the region" % [_chunks.size, _chunks.size, _chunks.count.x, _chunks.count.y],
		"Terrain planned %d, drawn %d; objects planned %d, drawn %d" % [tally[0], tally[1], tally[2], tally[3]],
		"Worker jobs running %d" % _jobs.size(),
	])
	_info.text = "\n".join(lines)
	_describe()
