extends Node2D

## Module 13's world view: three map levels, each drawn in its own frame round a moving anchor (a floating
## origin, since the world is millions of metres wide), each zoom held to its RANGES times its standard. A wheel
## notch past the range runs a transition: a cover closes (clouds between L3 and L2, an iris between L2 and
## L1) while the camera keeps zooming, the new level loads behind it, and the cover opens on it. L2 and L1
## are streamed in chunks (WorldChunkStore) planned on worker threads; L3 is one map, a sheet on a table.

const LEVEL_NAMES: Array[String] = ["L3", "L2", "L1"]
## Metres a cell, per level.
const METRES: Array[int] = [16384, 128, 1]
## Child cells per parent cell side.
const SPLIT: int = 128
## Pixels a cell in every level's frame.
const CELL_PX: float = 32.0
## Cells a chunk side, for L2 and L1.
const CHUNK: Array[int] = [0, 64, 32]
## Plans kept per level.
const CAP: Array[int] = [0, 2048, 4096]
## Each level's zoom stays between these times its standard; L3 lets you look closer.
const RANGES: Array[Vector2] = [Vector2(0.7, 5.0), Vector2(0.7, 1.5), Vector2(0.7, 1.5)]
## On-screen pixels a cell at the standard zoom, for L2 and L1; L3's standard fits the whole map.
const STANDARD_PX: Array[float] = [0.0, 6.0, 16.0]
const WHEEL_STEP: float = 1.15
## Wheel notches past a level's limit that are only held, per level (L3 holds longer before L2), and how long,
## in seconds, a pause may be before the count starts again; one notch more changes level.
const HOLD_NOTCHES: Array[int] = [5, 2, 2]
const HOLD_GAP: float = 0.6
## How far, as a zoom factor, a pinch must keep going past a limit before the level changes, per level.
const PINCH_PAST: Array[float] = [1.6, 1.35, 1.35]
## Seconds the cover takes to close, and to open.
const COVER_TIME: float = 0.35
## How much further the camera zooms while the cover closes, and how far off standard it opens from.
const PUSH: float = 1.6
const SETTLE: float = 1.12
## Longest a loading cover is held, in seconds.
const LOAD_CAP: float = 5.0
## The camera is re-anchored once this far, in pixels, from its frame's origin.
const REANCHOR_PX: float = 65536.0
## Chunks planned and drawn this far round the view; nodes freed past KEEP.
const RING: int = 1
const KEEP: int = 3
const MAX_JOBS: int = 3
const CLOUDS := preload("res://13. World Generator/art/clouds.gdshader")
const IRIS := preload("res://13. World Generator/art/iris.gdshader")
const L3_MAP := preload("res://13. World Generator/art/l3_map.gdshader")
const WATER_LINE := preload("res://13. World Generator/art/water_line.gdshader")
const TABLE := preload("res://13. World Generator/art/table.gdshader")
const SURYA := preload("res://Global/Asset/Map/surya.png")
## Table drawn round the sheet, in cells, and the brass sun weights' size.
const TABLE_CELLS: int = 96
const SURYA_CELLS: float = 14.0
## Table shown round the sheet at L3's standard zoom, and how far past the sheet the camera may look, in cells.
const SHEET_VIEW: float = 14.0
const TABLE_VIEW: float = 16.0
@export var world_seed: int = 0

@onready var _camera: Camera2D = $Camera2D
@onready var _world_root: Node2D = $World
@onready var _ui: Control = $UI/Root

var _level: int = 0
var _roots: Array[Node2D] = []
## Each level's anchor: the level cell drawn at its frame's origin.
var _anchor: Array[Vector2i] = [Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO]
var _stores: Array[WorldChunkStore] = [null, null, null]
var _jobs: Dictionary = {}
## "" when idle, else closing, loading or opening.
var _phase: StringName = &""
var _clouds_kind: bool = true
var _going_down: bool = true
var _cover_point: Vector2
var _load_started: float = 0.0
var _load_counts := Vector2i.ZERO
var _cover: Control
var _clouds: ColorRect
var _iris: ColorRect
var _cover_label: Label
var _info: Label
## Notches pushed past the current limit (+ in, - out) and when the last came.
var _held: int = 0
var _held_at: float = 0.0
## Fingers down (index -> screen position), the last pinch spread, and how far the pinch has gone past a limit.
var _touches: Dictionary = {}
var _spread: float = 0.0
var _past: float = 1.0
var _legend: WorldMapKey
var _hold_mark: WorldHoldMark
## The map mode: -1 biomes, else an index into WorldMap.MODES; and the L3 map's material.
var _mode: int = -1
var _map_material: ShaderMaterial
var _mode_bar: WorldModeToggle
## L3, the world map; its fields are drawn by the map shader and chunks read their parent colours from it.
var _map: WorldMap
## The river lines, shown on L3.
var _river_lines: Node2D

func _ready() -> void:
	# Dark past the poles, so the ice caps read as land.
	RenderingServer.set_default_clear_color(Color8(24, 28, 36))
	for level in 3:
		var root := Node2D.new()
		root.name = LEVEL_NAMES[level]
		root.visible = level == 0
		_world_root.add_child(root)
		_roots.append(root)
	_stores[1] = WorldChunkStore.new(CHUNK[1], WorldMap.SIZE * SPLIT, CAP[1])
	_stores[2] = WorldChunkStore.new(CHUNK[2], WorldMap.SIZE * SPLIT * SPLIT, CAP[2])
	_draw_l3()
	_build_cover()
	_info = Label.new()
	_info.position = Vector2(12, 8)
	_ui.add_child(_info)
	_build_legend()
	_hold_mark = WorldHoldMark.new()
	_ui.add_child(_hold_mark)
	_hold_mark.anchor_left = 0.5
	_hold_mark.anchor_right = 0.5
	_hold_mark.anchor_top = 0.5
	_hold_mark.anchor_bottom = 0.5
	_hold_mark.offset_left = -_hold_mark.size.x * 0.5
	_hold_mark.offset_right = _hold_mark.size.x * 0.5
	_hold_mark.offset_top = -_hold_mark.size.y * 0.5
	_hold_mark.offset_bottom = _hold_mark.size.y * 0.5
	var size := Vector2(WorldMap.SIZE) * CELL_PX
	_camera.zoom = Vector2.ONE * _standard(0)
	_camera.position = size * 0.5

func _exit_tree() -> void:
	for task: int in _jobs:
		WorkerThreadPool.wait_for_task_completion(task)

func _process(_delta: float) -> void:
	for task: int in _jobs.keys():
		if WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
			var job: Dictionary = _jobs[task]
			_jobs.erase(task)
			_stores[job["level"]].put(job["at"], {"image": job["image"]}, job["usec"])
	if _phase != &"closing":
		if _level == 0:
			_clamp_l3()
		else:
			_reanchor()
			_stream()
	if _phase == &"loading":
		_cover_label.text = "Loading %s  %d / %d" % [LEVEL_NAMES[_level], _load_counts.x, _load_counts.y]
		if _load_counts.x >= _load_counts.y or Time.get_ticks_msec() / 1000.0 - _load_started > LOAD_CAP:
			_open()
	# A pause in a held zoom empties the mark, as it does the count.
	if _held != 0 and Time.get_ticks_msec() / 1000.0 - _held_at > HOLD_GAP:
		_held = 0
		_hold_mark.fade()
	if _touches.size() < 2 and _past != 1.0:
		_past = 1.0
		_hold_mark.fade()
	_report()

## The wheel zooms toward the mouse inside the level's range; past it, a few more notches change level.
func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	var step := 0.0
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		step = WHEEL_STEP
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		step = 1.0 / WHEEL_STEP
	if step == 0.0:
		return
	get_viewport().set_input_as_handled()
	if _phase != &"":
		return
	var zoom := _camera.zoom.x * step
	var at := get_global_mouse_position()
	var screen := get_viewport().get_mouse_position()
	var standard := _standard(_level)
	var range_ := RANGES[_level]
	# A notch counts as a push only when the zoom already sits at the limit it goes past.
	var push := 0
	if zoom > standard * range_.y and _camera.zoom.x >= standard * range_.y * 0.999 and _level < 2:
		push = 1
	elif zoom < standard * range_.x and _camera.zoom.x <= standard * range_.x * 1.001 and _level > 0:
		push = -1
	_zoom_at(at, clampf(zoom, standard * range_.x, standard * range_.y), screen)
	# At a limit the first notches only hold; keep scrolling and the level changes.
	var now := Time.get_ticks_msec() / 1000.0
	if push == 0 or signi(_held) != push or now - _held_at > HOLD_GAP:
		_held = 0
	_held_at = now
	if push != 0:
		_held += push
		if absi(_held) > HOLD_NOTCHES[_level]:
			_held = 0
			_hold_mark.fade()
			_close(_level + push, at, screen)
		else:
			_show_hold(_level + push, float(absi(_held)) / HOLD_NOTCHES[_level])

## One finger pans (a left-button drag too: the project turns mouse drags into touches); two fingers pinch to zoom on their middle, and a pinch kept
## going past a limit changes level.
func _unhandled_input(event: InputEvent) -> void:
	if _phase != &"":
		_touches.clear()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		_past = 1.0
		_spread = _pinch_spread()
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() == 1:
			_camera.position -= event.relative / _camera.zoom.x
		elif _touches.size() == 2:
			var spread := _pinch_spread()
			if _spread > 0.0:
				_pinch(spread / _spread)
			_spread = spread

func _pinch_spread() -> float:
	if _touches.size() != 2:
		return 0.0
	var points: Array = _touches.values()
	return (points[0] as Vector2).distance_to(points[1])

## Zooms by `factor` on the middle of the two fingers; past a limit the pinch is counted, and once it has gone
## PINCH_PAST further the level changes.
func _pinch(factor: float) -> void:
	var points: Array = _touches.values()
	var screen: Vector2 = ((points[0] as Vector2) + (points[1] as Vector2)) * 0.5
	var at := _camera.position + (screen - get_viewport_rect().size * 0.5) / _camera.zoom.x
	var standard := _standard(_level)
	var range_ := RANGES[_level]
	var zoom := _camera.zoom.x * factor
	var clamped := clampf(zoom, standard * range_.x, standard * range_.y)
	_zoom_at(at, clamped, screen)
	_past = _past * zoom / clamped if not is_equal_approx(zoom, clamped) else 1.0
	var target := _level + (1 if _past > 1.0 else -1)
	if _past != 1.0 and target >= 0 and target <= 2:
		_show_hold(target, absf(log(_past)) / log(PINCH_PAST[_level]))
	if _past > PINCH_PAST[_level] and _level < 2:
		_past = 1.0
		_hold_mark.fade()
		_close(_level + 1, at, screen)
	elif _past < 1.0 / PINCH_PAST[_level] and _level > 0:
		_past = 1.0
		_hold_mark.fade()
		_close(_level - 1, at, screen)

## The hold mark, `amount` full, leading to `level`.
func _show_hold(level: int, amount: float) -> void:
	_hold_mark.steps = HOLD_NOTCHES[_level]
	_hold_mark.label = LEVEL_NAMES[level]
	_hold_mark.show_fill(amount)

## Sets the zoom, keeping frame point `at` at `screen`.
func _zoom_at(at: Vector2, zoom: float, screen: Vector2) -> void:
	_camera.zoom = Vector2(zoom, zoom)
	_camera.position = at - (screen - get_viewport_rect().size * 0.5) / zoom

## `level`'s standard zoom.
func _standard(level: int) -> float:
	if level == 0:
		var view := get_viewport_rect().size
		var sheet := (Vector2(WorldMap.SIZE) + Vector2.ONE * SHEET_VIEW * 2.0) * CELL_PX
		return minf(view.x / sheet.x, view.y / sheet.y)
	return STANDARD_PX[level] / CELL_PX

## Frame point `at` of `level` in that level's cells, as 64-bit floats [x, y].
func _cells_of(level: int, at: Vector2) -> PackedFloat64Array:
	return PackedFloat64Array([float(_anchor[level].x) + at.x / CELL_PX, float(_anchor[level].y) + at.y / CELL_PX])

## What the camera shows in `level`'s cells.
func _view_cells(level: int) -> Rect2i:
	var half := get_viewport_rect().size * 0.5 / _camera.zoom.x
	var from := _cells_of(level, _camera.position - half)
	var to := _cells_of(level, _camera.position + half)
	return Rect2i(floori(from[0]), floori(from[1]), ceili(to[0]) - floori(from[0]), ceili(to[1]) - floori(from[1]))

## The L3 map as one sheet on the table, drawn by the map shader from its fields.
func _draw_l3() -> void:
	_draw_table()
	_map = WorldMap.make(world_seed)
	var material := ShaderMaterial.new()
	material.shader = L3_MAP
	_map_material = material
	material.set_shader_parameter(&"table", ImageTexture.create_from_image(WorldMap.table()))
	material.set_shader_parameter(&"sea", WorldMap.SEA)
	material.set_shader_parameter(&"mountain", WorldMap.MOUNTAIN)
	material.set_shader_parameter(&"snow", WorldMap.SNOW)
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(_map.fields_image())
	sprite.material = material
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.scale = Vector2(CELL_PX, CELL_PX)
	_roots[0].add_child(sprite)
	_draw_rivers()
	var map := Vector2(WorldMap.SIZE) * CELL_PX
	for corner: Vector2 in [Vector2.ZERO, Vector2(1, 0), Vector2(0, 1), Vector2.ONE]:
		var weight := Sprite2D.new()
		weight.texture = SURYA
		weight.scale = Vector2.ONE * SURYA_CELLS * CELL_PX / SURYA.get_width()
		weight.position = corner * map + (corner * 2.0 - Vector2.ONE) * 2.0 * CELL_PX
		_roots[0].add_child(weight)

## L3's rivers as lines over the map, each widening with its flow, in the map's own shallow water (the water
## line shader matches its colour and fibres). Each has a thin sea-blue edge that stops short of its mouth, and
## every edge is drawn under every river, so rivers, lakes and the sea join as one water.
func _draw_rivers() -> void:
	_river_lines = Node2D.new()
	_roots[0].add_child(_river_lines)
	var edges := Node2D.new()
	var waters := Node2D.new()
	_river_lines.add_child(edges)
	_river_lines.add_child(waters)
	var material := ShaderMaterial.new()
	material.shader = WATER_LINE
	material.set_shader_parameter(&"cell", CELL_PX)
	var edge := _faded(Color(0.17, 0.29, 0.38))
	for river: Dictionary in _map.rivers:
		var points: PackedVector2Array = river["points"]
		var flows: PackedFloat32Array = river["flows"]
		var widest := WorldMap.river_width(flows[flows.size() - 1])
		var curve := Curve.new()
		for k in flows.size():
			curve.add_point(Vector2(float(k) / (flows.size() - 1), WorldMap.river_width(flows[k]) / widest))
		var outline := _river_line(_trimmed(points, 0.8), widest + 0.14, curve)
		outline.default_color = edge
		edges.add_child(outline)
		var water := _river_line(points, widest, curve)
		water.material = material
		waters.add_child(water)

func _river_line(points: PackedVector2Array, width: float, curve: Curve) -> Line2D:
	var line := Line2D.new()
	for p in points:
		line.add_point(p * CELL_PX)
	line.width = width * CELL_PX
	line.width_curve = curve
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	return line

## `points` with `length` (in cells) cut off their end.
static func _trimmed(points: PackedVector2Array, length: float) -> PackedVector2Array:
	var out := points.duplicate()
	var left := length
	while out.size() > 2 and left > 0.0:
		var last := out[out.size() - 1]
		var before := out[out.size() - 2]
		var span := last.distance_to(before)
		if span > left:
			out[out.size() - 1] = last.move_toward(before, left)
			break
		left -= span
		out.remove_at(out.size() - 1)
	return out

## `c` as the map shader shows pigment on daluang: a little faded and warmed.
static func _faded(c: Color) -> Color:
	var paper := Color(0.95, 0.86, 0.68)
	return Color(lerpf(c.r, c.r * paper.r, 0.45), lerpf(c.g, c.g * paper.g, 0.45), lerpf(c.b, c.b * paper.b, 0.45))

## Round the map: the sheet's margin with its tumpal border and torn edge, then the teak table.
func _draw_table() -> void:
	var map := Vector2(WorldMap.SIZE) * CELL_PX
	var material := ShaderMaterial.new()
	material.shader = TABLE
	material.set_shader_parameter(&"cell", CELL_PX)
	material.set_shader_parameter(&"map_size", map)
	var white := Image.create_empty(1, 1, false, Image.FORMAT_RGB8)
	white.fill(Color.WHITE)
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(white)
	sprite.material = material
	sprite.centered = false
	var depth := TABLE_CELLS * CELL_PX
	sprite.position = -Vector2.ONE * depth
	sprite.scale = map + Vector2.ONE * depth * 2.0
	_roots[0].add_child(sprite)

## The L3 key, bottom left, and the map mode slips, bottom right; both shown on L3 only. Keys 1-4 pick too.
func _build_legend() -> void:
	_legend = WorldMapKey.new()
	_ui.add_child(_legend)
	_mode_bar = WorldModeToggle.new()
	_ui.add_child(_mode_bar)
	var names: Array[String] = ["Biome"]
	for mode: Dictionary in WorldMap.MODES:
		names.append(mode["name"])
	_mode_bar.names = names
	_mode_bar.picked.connect(func(k: int) -> void: _set_mode(k - 1))
	# Pinned bottom right from its own size.
	_mode_bar.anchor_left = 1.0
	_mode_bar.anchor_right = 1.0
	_mode_bar.anchor_top = 1.0
	_mode_bar.anchor_bottom = 1.0
	_mode_bar.offset_left = -12.0 - _mode_bar.custom_minimum_size.x
	_mode_bar.offset_right = -12.0
	_mode_bar.offset_top = -12.0 - _mode_bar.custom_minimum_size.y
	_mode_bar.offset_bottom = -12.0
	_set_mode(-1)

## Shows L3 by biome (-1) or by one of WorldMap.MODES, and fits the key to it.
func _set_mode(mode: int) -> void:
	_mode = mode
	if mode < 0:
		_map_material.set_shader_parameter(&"field", -1)
		_legend.title = "Biomes"
		_legend.entries = WorldMap.WATERS + WorldMap.BIOMES
	else:
		var entry: Dictionary = WorldMap.MODES[mode]
		_map_material.set_shader_parameter(&"field", entry["field"])
		_map_material.set_shader_parameter(&"ramp", WorldMap.ramp(entry))
		_legend.title = entry["name"]
		_legend.entries = entry["bands"].map(func(band: Array) -> Array: return [band[2], band[1]])
	_mode_bar.selected = mode + 1
	# Pinned bottom left from its own size, which it has just set.
	_legend.anchor_top = 1.0
	_legend.anchor_bottom = 1.0
	_legend.offset_left = 12.0
	_legend.offset_right = 12.0 + _legend.custom_minimum_size.x
	_legend.offset_top = -12.0 - _legend.custom_minimum_size.y
	_legend.offset_bottom = -12.0

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and _level == 0 and key.keycode >= KEY_1 and key.keycode <= KEY_4:
		_set_mode(key.keycode - KEY_1 - 1)

## Keeps the camera over the table: no further than TABLE_VIEW cells past the sheet's edge.
func _clamp_l3() -> void:
	var map := Vector2(WorldMap.SIZE) * CELL_PX
	var half := get_viewport_rect().size * 0.5 / _camera.zoom.x
	var margin := TABLE_VIEW * CELL_PX
	for axis in 2:
		if half[axis] * 2.0 >= map[axis] + margin * 2.0:
			_camera.position[axis] = map[axis] * 0.5
		else:
			_camera.position[axis] = clampf(_camera.position[axis], half[axis] - margin, map[axis] - half[axis] + margin)

## Moves the current level's anchor under the camera once it strays far, so frame numbers stay small.
func _reanchor() -> void:
	if absf(_camera.position.x) < REANCHOR_PX and absf(_camera.position.y) < REANCHOR_PX:
		return
	var shift := Vector2i(floori(_camera.position.x / CELL_PX), floori(_camera.position.y / CELL_PX))
	_set_anchor(_level, _anchor[_level] + shift)
	_camera.position -= Vector2(shift) * CELL_PX

## Sets `level`'s anchor (x wrapped) and redraws its chunks where they now fall.
func _set_anchor(level: int, anchor: Vector2i) -> void:
	var store := _stores[level]
	if store != null:
		anchor.x = posmod(anchor.x, store.chunks.x * store.size)
		for at: Vector2i in store.drawn:
			(store.drawn[at] as Node).queue_free()
		store.drawn.clear()
	_anchor[level] = anchor

## Plans and draws the current level's chunks round the view, nearest first; frees far ones.
func _stream() -> void:
	var store := _stores[_level]
	var view := _view_cells(_level)
	var wanted := store.around(view, RING)
	var most := maxi(OS.get_processor_count() - 1, MAX_JOBS) if _phase == &"loading" else MAX_JOBS
	for at in wanted:
		var key := store.wrapped(at)
		if store.plans.has(key):
			store.touch(key)
			if not store.drawn.has(at):
				_draw_chunk(_level, at, store.plans[key])
		elif not store.busy.has(key) and _jobs.size() < most:
			_plan_chunk(_level, key)
	var keep: Dictionary = {}
	for at in store.around(view, KEEP):
		keep[at] = true
	for at: Vector2i in store.drawn.keys():
		if not keep.has(at):
			(store.drawn[at] as Node).queue_free()
			store.drawn.erase(at)
	store.trim()
	var need := store.around(view, 0)
	_load_counts = Vector2i(need.filter(func(a: Vector2i) -> bool: return store.drawn.has(a)).size(), need.size())

func _plan_chunk(level: int, at: Vector2i) -> void:
	var store := _stores[level]
	store.busy[at] = true
	var job := {"level": level, "at": at}
	var size := store.size
	var map := _map
	_jobs[WorkerThreadPool.add_task(func() -> void:
		var started := Time.get_ticks_usec()
		job["image"] = WorldPlaceholder.chunk_image(level, at, size, map)
		job["usec"] = Time.get_ticks_usec() - started, false, "world chunk")] = job

func _draw_chunk(level: int, at: Vector2i, plan: Dictionary) -> void:
	var store := _stores[level]
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(plan["image"])
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(CELL_PX, CELL_PX)
	sprite.position = Vector2(at * store.size - _anchor[level]) * CELL_PX
	_roots[level].add_child(sprite)
	store.drawn[at] = sprite

## The cover over the screen: a cloud layer with its backdrop, and the iris.
func _build_cover() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_cover = Control.new()
	_cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.visible = false
	layer.add_child(_cover)
	_clouds = ColorRect.new()
	_clouds.set_anchors_preset(Control.PRESET_FULL_RECT)
	_clouds.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var height := NoiseTexture2D.new()
	height.width = 1024
	height.height = 1024
	height.seamless = true
	height.normalize = true
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.fractal_octaves = 5
	noise.frequency = 0.006
	height.noise = noise
	var clouds := ShaderMaterial.new()
	clouds.shader = CLOUDS
	clouds.set_shader_parameter(&"height", height)
	_clouds.material = clouds
	_cover.add_child(_clouds)
	_iris = ColorRect.new()
	_iris.set_anchors_preset(Control.PRESET_FULL_RECT)
	_iris.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = IRIS
	_iris.material = material
	_cover.add_child(_iris)
	_cover_label = Label.new()
	_cover_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_cover_label.position.y -= 60
	_cover.add_child(_cover_label)

## Lays the cover `t` shut (0 open, 1 shut): clouds rise out of their height map until they fill the
## screen, drawn at `far` times their size; the iris shuts on `_cover_point`.
func _set_cover(t: float, far: float) -> void:
	var view := get_viewport_rect().size
	if _clouds_kind:
		var material := _clouds.material as ShaderMaterial
		material.set_shader_parameter(&"size", view)
		material.set_shader_parameter(&"cover", t)
		material.set_shader_parameter(&"scale", 0.4 / far)
	else:
		var material := _iris.material as ShaderMaterial
		material.set_shader_parameter(&"size", view)
		material.set_shader_parameter(&"center", _cover_point)
		material.set_shader_parameter(&"radius", (1.0 - t) * view.length())

## Starts a transition to `to`: the camera keeps zooming on `at` (at `screen`) while the cover shuts.
func _close(to: int, at: Vector2, screen: Vector2) -> void:
	_phase = &"closing"
	_camera.manual_control = false
	_going_down = to > _level
	_clouds_kind = mini(to, _level) == 0
	_cover_point = screen if _going_down else get_viewport_rect().size * 0.5
	if not _going_down:
		at = _camera.position
		screen = _cover_point
	_clouds.visible = _clouds_kind
	_iris.visible = not _clouds_kind
	_cover_label.text = ""
	_cover_label.modulate = Color8(42, 32, 22) if _clouds_kind else Color8(231, 214, 172)
	_cover.visible = true
	var far := 0.85 if _going_down else 1.2
	_set_cover(0.0, far)
	var from := _camera.zoom.x
	var push := PUSH if _going_down else 1.0 / PUSH
	var cells := _cells_of(_level, at)
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_method(func(z: float) -> void: _zoom_at(at, z, screen), from, from * push, COVER_TIME)
	tween.tween_method(func(t: float) -> void: _set_cover(t, far), 0.0, 1.0, COVER_TIME).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(func() -> void: _load(to, cells, screen))

## Behind the shut cover: shows level `to` with level cell `cells` of the old level at `screen`, at
## just off its standard zoom, and waits for what the view needs.
func _load(to: int, cells: PackedFloat64Array, screen: Vector2) -> void:
	var scale := float(SPLIT) if to > _level else 1.0 / SPLIT
	var x := cells[0] * scale
	var y := cells[1] * scale
	_roots[_level].visible = false
	_level = to
	_roots[to].visible = true
	var zoom := _standard(to) / SETTLE if _going_down else _standard(to) * SETTLE
	var at: Vector2
	if to == 0:
		at = Vector2(x, y) * CELL_PX
	else:
		_set_anchor(to, Vector2i(floori(x), floori(y)))
		at = Vector2(x - _anchor[to].x, y - _anchor[to].y) * CELL_PX
	_zoom_at(at, zoom, screen)
	_phase = &"loading"
	_load_started = Time.get_ticks_msec() / 1000.0
	_load_counts = Vector2i.ZERO
	if to == 0:
		_open()

## Opens the cover on the new level while the zoom settles to its standard.
func _open() -> void:
	_phase = &"opening"
	_cover_label.text = ""
	var screen := _cover_point
	var at := _camera.position + (screen - get_viewport_rect().size * 0.5) / _camera.zoom.x
	var far := 1.2 if _going_down else 0.85
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(z: float) -> void: _zoom_at(at, z, screen), _camera.zoom.x, _standard(_level), COVER_TIME)
	tween.tween_method(func(t: float) -> void: _set_cover(t, far), 1.0, 0.0, COVER_TIME).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func() -> void:
		_cover.visible = false
		_camera.manual_control = true
		_phase = &"")

func _report() -> void:
	_legend.visible = _level == 0
	_mode_bar.visible = _level == 0
	var cells := _cells_of(_level, _camera.position)
	var km := PackedFloat64Array([cells[0] * METRES[_level] / 1000.0, cells[1] * METRES[_level] / 1000.0])
	var lines: Array[String] = ["%s, %s a cell: zoom ×%.3f (×%.3f to ×%.3f)%s" % [LEVEL_NAMES[_level],
		"%d m" % METRES[_level] if METRES[_level] < 1000 else "%.1f km" % (METRES[_level] / 1000.0),
		_camera.zoom.x, _standard(_level) * RANGES[_level].x, _standard(_level) * RANGES[_level].y,
		"" if _phase == &"" else ", " + _phase], "At %.1f km east, %.1f km south" % [km[0], km[1]]]
	for level in [1, 2]:
		var store := _stores[level]
		lines.append("%s: %d drawn, %d planned (%.2f ms a plan)" % [LEVEL_NAMES[level], store.drawn.size(),
			store.plans.size(), store.plan_usec / 1000.0 / maxi(store.planned, 1)])
	lines.append("Wheel: zoom; one notch past the range changes level. Arrows: pan.")
	_info.text = "\n".join(lines)
