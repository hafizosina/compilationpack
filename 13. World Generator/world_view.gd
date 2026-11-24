extends Node2D

## Module 13's world view: three map levels, each drawn in its own frame round a moving anchor (a floating
## origin, since the world is millions of metres wide), each zoom held to RANGE times its standard. A wheel
## notch past the range runs a transition: a cover closes (clouds between L3 and L2, an iris between L2 and
## L1) while the camera keeps zooming, the new level loads behind it, and the cover opens on it. L2 and L1
## are streamed in chunks (WorldChunkStore) planned on worker threads; L3 is one map, wrapping east-west.

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
## A level's zoom stays between these times its standard.
const RANGE := Vector2(0.7, 1.5)
## On-screen pixels a cell at the standard zoom, for L2 and L1; L3's standard fits the whole map.
const STANDARD_PX: Array[float] = [0.0, 6.0, 16.0]
const WHEEL_STEP: float = 1.15
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
## The L3 map, a pixel a cell; chunks read their parent colours from it.
var _l3_image: Image

func _ready() -> void:
	# Dark past the poles, so the ice caps read as land.
	RenderingServer.set_default_clear_color(Color8(24, 28, 36))
	for level in 3:
		var root := Node2D.new()
		root.name = LEVEL_NAMES[level]
		root.visible = level == 0
		_world_root.add_child(root)
		_roots.append(root)
	_stores[1] = WorldChunkStore.new(CHUNK[1], WorldPlaceholder.L3 * SPLIT, CAP[1])
	_stores[2] = WorldChunkStore.new(CHUNK[2], WorldPlaceholder.L3 * SPLIT * SPLIT, CAP[2])
	_draw_l3()
	_build_cover()
	_info = Label.new()
	_info.position = Vector2(12, 8)
	_ui.add_child(_info)
	var size := Vector2(WorldPlaceholder.L3) * CELL_PX
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
			_wrap_l3()
		else:
			_reanchor()
			_stream()
	if _phase == &"loading":
		_cover_label.text = "Loading %s  %d / %d" % [LEVEL_NAMES[_level], _load_counts.x, _load_counts.y]
		if _load_counts.x >= _load_counts.y or Time.get_ticks_msec() / 1000.0 - _load_started > LOAD_CAP:
			_open()
	_report()

## The wheel zooms toward the mouse inside the level's range; a notch past it changes level.
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
	if zoom > standard * RANGE.y and _level < 2:
		_close(_level + 1, at, screen)
	elif zoom < standard * RANGE.x and _level > 0:
		_close(_level - 1, at, screen)
	else:
		_zoom_at(at, clampf(zoom, standard * RANGE.x, standard * RANGE.y), screen)

## Sets the zoom, keeping frame point `at` at `screen`.
func _zoom_at(at: Vector2, zoom: float, screen: Vector2) -> void:
	_camera.zoom = Vector2(zoom, zoom)
	_camera.position = at - (screen - get_viewport_rect().size * 0.5) / zoom

## `level`'s standard zoom.
func _standard(level: int) -> float:
	if level == 0:
		var view := get_viewport_rect().size
		var map := Vector2(WorldPlaceholder.L3) * CELL_PX
		return minf(view.x / map.x, view.y / map.y)
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

## The L3 map, three copies side by side so it wraps.
func _draw_l3() -> void:
	_l3_image = WorldPlaceholder.l3_image(world_seed)
	var texture := ImageTexture.create_from_image(_l3_image)
	for k in [-1, 0, 1]:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.scale = Vector2(CELL_PX, CELL_PX)
		sprite.position = Vector2(k * WorldPlaceholder.L3.x * CELL_PX, 0)
		_roots[0].add_child(sprite)

## Keeps the camera over the middle copy of L3.
func _wrap_l3() -> void:
	var width := WorldPlaceholder.L3.x * CELL_PX
	if _camera.position.x < 0.0 or _camera.position.x >= width:
		_camera.position.x = fposmod(_camera.position.x, width)

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
	var l3 := _l3_image
	_jobs[WorkerThreadPool.add_task(func() -> void:
		var started := Time.get_ticks_usec()
		job["image"] = WorldPlaceholder.chunk_image(level, at, size, l3)
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
		at = Vector2(fposmod(x, WorldPlaceholder.L3.x), y) * CELL_PX
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
	var cells := _cells_of(_level, _camera.position)
	var km := PackedFloat64Array([cells[0] * METRES[_level] / 1000.0, cells[1] * METRES[_level] / 1000.0])
	var lines: Array[String] = ["%s, %s a cell: zoom ×%.3f (×%.3f to ×%.3f)%s" % [LEVEL_NAMES[_level],
		"%d m" % METRES[_level] if METRES[_level] < 1000 else "%.1f km" % (METRES[_level] / 1000.0),
		_camera.zoom.x, _standard(_level) * RANGE.x, _standard(_level) * RANGE.y,
		"" if _phase == &"" else ", " + _phase], "At %.1f km east, %.1f km south" % [km[0], km[1]]]
	for level in [1, 2]:
		var store := _stores[level]
		lines.append("%s: %d drawn, %d planned (%.2f ms a plan)" % [LEVEL_NAMES[level], store.drawn.size(),
			store.plans.size(), store.plan_usec / 1000.0 / maxi(store.planned, 1)])
	lines.append("Wheel: zoom; one notch past the range changes level. Arrows: pan.")
	_info.text = "\n".join(lines)
