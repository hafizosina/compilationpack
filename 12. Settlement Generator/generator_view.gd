extends Node2D

## The terrain generator's viewer: pick a map, its water and a seed, press Generate, and it is planned
## on a worker thread, then sent through module 10's real build pipeline, drawn, and checked
## (EcsTerrainCheck). "Region (L2)" plans the whole region; a click on it zooms into the L1 window
## under the mouse (EcsTerrainGenerator.refine, also on a worker), checked against its region too,
## and Back returns. Nodes and a zone tint can be shown or hidden.

const DEFS := "res://12. Settlement Generator/defs/settlements/"
## Maps on their own, then the L2 region.
const MAPS: Array[StringName] = [&"hamlet", &"village", &"town", &"region"]
const WATER_NAMES: Array[String] = ["The def's", "Lake", "River", "Coast", "River to the sea"]
## The def an L1 window takes its size, shore and nodes from.
const WINDOW_DEF: StringName = &"town"
## L1 cells per L2 cell side.
const ZOOM: int = 8
## Zone tint, most specific zone first: [zone, colour].
const TINTS := [
	[EcsNodeSpawnDef.Zone.SHALLOW, Color(0.3, 0.9, 1.0)], [EcsNodeSpawnDef.Zone.SHORE, Color(1.0, 0.9, 0.3)],
	[EcsNodeSpawnDef.Zone.ROCK_INNER, Color(0.25, 0.25, 0.3)], [EcsNodeSpawnDef.Zone.ROCK, Color(0.6, 0.6, 0.65)],
	[EcsNodeSpawnDef.Zone.DEEP_FOREST, Color(0.0, 0.3, 0.1)], [EcsNodeSpawnDef.Zone.FOREST_EDGE, Color(0.6, 0.9, 0.3)],
	[EcsNodeSpawnDef.Zone.FOREST, Color(0.2, 0.6, 0.2)],
]
## Ticks after a generation before the map has settled and is reported.
const SETTLE: int = 4

@export var catalog: EcsTownCatalog
@export var entity_catalog: EcsEntityCatalog

@onready var _layers_root: Node = $World/TilemapGroup
@onready var _entities_root: Node2D = $World/Entities
@onready var _zones: Sprite2D = $World/Zones
@onready var _camera: Camera2D = $Camera2D
@onready var _root: Control = $UI/Root

var _panel: PanelContainer
var _map: OptionButton
var _water: OptionButton
var _seed: SpinBox
var _back: Button
var _generate_button: Button
var _info: Label
var _outline: Line2D
var _world: EcsWorld
var _manager: EcsEntityManager
var _scheduler: EcsScheduler
var _build: EcsBuildCommandSystem
## What is shown: its def and plan.
var _def: EcsSettlementDef
var _plan: Dictionary = {}
## The region and its plan while the region or one of its windows is shown, else null.
var _region: EcsSettlementDef
var _region_plan: Dictionary = {}
var _region_seed: int = 0
## The window shown, in region cells; (-1, -1) while the region itself is.
var _window_at: Vector2i = Vector2i(-1, -1)
var _settle: int = 0
## The worker task planning a map, or -1; what it was asked for, and what it gave back.
var _task: int = -1
var _job: Dictionary = {}
var _result: Dictionary = {}

func _ready() -> void:
	catalog.number()
	# Builds the catalog's lookup here, so the worker only ever reads it.
	entity_catalog.has_def(&"tree")
	_manager = EcsEntityManager.new(_entities_root)
	_outline = Line2D.new()
	_outline.width = 24.0
	_outline.default_color = Color(1.0, 0.85, 0.2)
	_outline.z_index = 30
	_outline.closed = true
	_outline.visible = false
	$World.add_child(_outline)
	_build_panel()
	_generate()

func _process(_delta: float) -> void:
	if _task != -1 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_busy(false)
		_planned()

func _physics_process(delta: float) -> void:
	if _scheduler == null:
		return
	_scheduler.run_all(_world, delta)
	if _settle > 0:
		_settle -= 1
		if _settle == 0:
			_report()

func _unhandled_input(event: InputEvent) -> void:
	if _region == null or _window_at != Vector2i(-1, -1) or _task != -1:
		return
	if event is InputEventMouseMotion:
		_outline.position = Vector2(_window_origin() * EcsTownGrid.CELL)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_zoom(_window_origin())

## The L1 window's top-left in region cells, centred on the mouse and kept inside the region.
func _window_origin() -> Vector2i:
	var window := _window_def().size / ZOOM
	return (EcsTownGrid.cell_at(get_global_mouse_position()) - window / 2).clamp(Vector2i.ZERO, _region.size - window)

func _window_def() -> EcsSettlementDef:
	return load(DEFS + "%s.tres" % WINDOW_DEF) as EcsSettlementDef

func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"DockPanel"
	_panel.position = Vector2(12, 12)
	_panel.custom_minimum_size = Vector2(300, 0)
	_root.add_child(_panel)
	var box := VBoxContainer.new()
	_panel.add_child(box)
	var title := Label.new()
	title.text = "Settlement terrain"
	title.theme_type_variation = &"DockTitle"
	box.add_child(title)
	var names: Array = MAPS.map(func(k: StringName) -> String: return String(k).capitalize())
	names[3] = "Region (L2)"
	_map = _option(box, "Map", names)
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
	_back = Button.new()
	_back.text = "Back to the region (L2)"
	_back.visible = false
	_back.pressed.connect(_show_region)
	box.add_child(_back)
	var nodes := CheckBox.new()
	nodes.text = "Nodes"
	nodes.button_pressed = true
	nodes.toggled.connect(func(on: bool) -> void: _entities_root.visible = on)
	box.add_child(nodes)
	var zones := CheckBox.new()
	zones.text = "Zone tint"
	zones.toggled.connect(func(on: bool) -> void: _zones.visible = on)
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

## Plans the chosen map from the inputs on a worker thread; `_planned` shows it.
func _generate() -> void:
	if _task != -1:
		return
	var def := (load(DEFS + "%s.tres" % MAPS[_map.selected]) as EcsSettlementDef).duplicate() as EcsSettlementDef
	if _water.selected > 0 and _water.selected - 1 != def.water:
		def.water = _water.selected - 1
		def.water_share = 0.03 if def.water == EcsSettlementDef.Water.RIVER else (0.18 if def.water == EcsSettlementDef.Water.RIVER_TO_SEA else 0.12)
	var rng_seed := int(_seed.value)
	_start({"kind": &"region" if MAPS[_map.selected] == &"region" else &"map", "def": def, "seed": rng_seed},
		func() -> Dictionary: return EcsTerrainGenerator.plan(def, rng_seed, catalog, entity_catalog))

## Runs `work` on a worker thread; `job` says what it is for.
func _start(job: Dictionary, work: Callable) -> void:
	_job = job
	_task = WorkerThreadPool.add_task(func() -> void: _result = work.call(), false, "settlement terrain")
	_busy(true)

func _busy(on: bool) -> void:
	_generate_button.disabled = on
	_generate_button.text = "Planning on a worker thread…" if on else "Generate"
	_back.disabled = on
	if on:
		_info.text = "Planning…"

## Shows what the worker planned.
func _planned() -> void:
	var def := _job["def"] as EcsSettlementDef
	match _job["kind"]:
		&"region":
			_region = def
			_region_plan = _result
			_region_seed = _job["seed"]
			_show_region()
		&"window":
			_window_at = _job["origin"]
			_outline.visible = false
			_back.visible = true
			_show(def, _result)
		_:
			_region = null
			_region_plan = {}
			_outline.visible = false
			_back.visible = false
			_show(def, _result)

func _show_region() -> void:
	_window_at = Vector2i(-1, -1)
	_back.visible = false
	var window := Vector2(_window_def().size / ZOOM * EcsTownGrid.CELL)
	_outline.points = PackedVector2Array([Vector2.ZERO, Vector2(window.x, 0), window, Vector2(0, window.y)])
	_outline.visible = true
	_show(_region, _region_plan)

## Zooms into the L1 window at `origin`, in region cells, planned on a worker thread.
func _zoom(origin: Vector2i) -> void:
	var window := _window_def()
	var region := _region
	var parent := _region_plan
	var rng_seed := _region_seed
	_start({"kind": &"window", "def": window, "origin": origin, "seed": rng_seed},
		func() -> Dictionary: return EcsTerrainGenerator.refine(parent, region, window, origin, ZOOM, rng_seed, catalog, entity_catalog))

## Sends `plan` through a new world, tints its zones, frames it, and reports once settled.
func _show(def: EcsSettlementDef, plan: Dictionary) -> void:
	_def = def
	_plan = plan
	_manager.clear()
	_world = EcsWorld.new()
	var grid := EcsTownGrid.make(def.size.x, def.size.y, catalog.terrain_id(&"grass"))
	grid.commands.append_array(plan["commands"])
	_world.add_singleton(grid)
	_world.add_singleton(EcsLifecycleSingleton.new())
	_world.add_singleton(EcsTownNavSingleton.new())
	_build = EcsBuildCommandSystem.new(catalog, entity_catalog)
	_scheduler = EcsScheduler.new()
	_scheduler \
		.add(EcsLifecycleSystem.new(_manager, entity_catalog)) \
		.add(_build) \
		.add(EcsTownNavSystem.new(catalog)) \
		.add(EcsTileSyncSystem.new(_layers_root, catalog))
	_settle = SETTLE
	_tint()
	_frame()
	_info.text = "Loading…"

## The zone tint: one pixel per cell, scaled to the grid.
func _tint() -> void:
	var w := _def.size.x
	var h := _def.size.y
	var zones := _plan["zones"] as PackedByteArray
	var image := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for i in w * h:
		for tint: Array in TINTS:
			if zones[i] & (1 << int(tint[0])):
				var colour: Color = tint[1]
				colour.a = 0.55
				image.set_pixel(i % w, i / w, colour)
				break
	_zones.texture = ImageTexture.create_from_image(image)
	_zones.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_zones.scale = Vector2(EcsTownGrid.CELL, EcsTownGrid.CELL)

## Zooms and centres the camera so the whole map fills the view right of the panel.
func _frame() -> void:
	var view := get_viewport_rect().size
	var left := _panel.get_rect().end.x + 12.0
	var room := Vector2(view.x - left, view.y)
	var span := Vector2(_def.size * EcsTownGrid.CELL)
	var zoom := minf(room.x / span.x, room.y / span.y)
	_camera.zoom = Vector2(zoom, zoom)
	_camera.position = span * 0.5 - Vector2(left * 0.5 / zoom, 0)

func _report() -> void:
	var zoomed := _window_at != Vector2i(-1, -1)
	var problems := EcsTerrainCheck.problems(_def, _plan, zoomed)
	if zoomed:
		problems.append_array(EcsTerrainCheck.follows(_region_plan, _region, _plan, _def, _window_at, ZOOM))
	var kinds := _plan["kinds"] as PackedByteArray
	var counts := [0, 0, 0, 0, 0]
	for kind in kinds:
		counts[kind] += 1
	var n := float(kinds.size())
	var nodes := PackedStringArray()
	var by_name := _plan["counts"] as Dictionary
	for key: StringName in by_name:
		nodes.append("%s %d" % [String(key).replace("_", " "), by_name[key]])
	var total := 0
	for stage: String in _plan["usec"]:
		total += int(_plan["usec"][stage])
	var what := "%s, %d×%d, %s" % [_def.display_name, _def.size.x, _def.size.y, WATER_NAMES[_def.water + 1].to_lower()]
	if zoomed:
		what = "L1 window at region cells %s, %d×%d (%d× the region)" % [_window_at, _def.size.x, _def.size.y, ZOOM]
	elif _region != null:
		what += ". Click to zoom into L1 there."
	what += ", seed %d" % int(_job["seed"])
	var lines := PackedStringArray([
		what,
		"Water %.0f%%, sand %.0f%%, rock %.0f%%, forest %.0f%%, grass %.0f%%" % [counts[1] / n * 100.0,
			counts[2] / n * 100.0, counts[3] / n * 100.0, counts[4] / n * 100.0, counts[0] / n * 100.0],
		"%d nodes: %s" % [(_plan["nodes"] as Array).size(), ", ".join(nodes)],
		"%d commands, %d refused" % [(_plan["commands"] as Array).size(), _build.refused],
		"Planned in %d ms" % (total / 1000),
		("Sound, and follows its region" if zoomed else "Sound") if problems.is_empty() else "Problems: " + "; ".join(problems),
	])
	_info.text = "\n".join(lines)
