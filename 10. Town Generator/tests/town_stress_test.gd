extends Node2D

## Brief §5's stress scene: N generated buildings, all rich and one size, 3 cells apart in a square, through the real
## pipeline. Prints load cost per stage, idle tick cost, then tick cost with wandering villagers.
##
##   "$GODOT" --headless --path . "res://10. Town Generator/tests/town_stress_test.tscn"
##   -- --n=500 --npcs=1000   one size and one villager count
##
## Without --headless (or F6 in the editor) it builds one town of `watch_buildings` and
## `watch_villagers` and runs it, with FPS and tick cost in the corner.

const CATALOG := preload("res://10. Town Generator/defs/town_catalog.tres")
const ENTITIES := preload("res://10. Town Generator/defs/entity_catalog.tres")
const TICK: float = 1.0 / 60.0
const SIZES: Array[int] = [100, 500, 1000]
const VILLAGERS: Array[int] = [0, 100, 500, 1000, 2000]
## Every building is this size, with GAP cells of street between and around them.
const BUILDING := Vector2i(10, 8)
const GAP: int = 3
## Every building rich: floored, most rooms, every optional piece of furniture.
const RICH: int = 2
const LOAD_TICKS: int = 4
const MEASURE_TICKS: int = 300
const FACINGS: Array[Vector2i] = [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]

## The town the live run builds.
@export var watch_buildings: int = 1000
@export var watch_villagers: int = 2000

@onready var _camera: Camera2D = $Camera2D

var _world: EcsWorld
var _scheduler: EcsScheduler
var _manager: EcsEntityManager
var _root: Node2D
var _bounds: Rect2
var _watching: bool = false
var _readout: Label
var _tick_usec: float = 0.0

func _ready() -> void:
	CATALOG.number()
	var sizes := SIZES
	var villagers := VILLAGERS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--n="):
			sizes = [arg.substr(4).to_int()]
		elif arg.begins_with("--npcs="):
			villagers = [arg.substr(7).to_int()]
	if DisplayServer.get_name() != "headless":
		_watch(sizes[0] if sizes.size() == 1 else watch_buildings, villagers[0] if villagers.size() == 1 else watch_villagers)
		return
	for n in sizes:
		_measure(n, villagers)
	get_tree().quit()

func _physics_process(_delta: float) -> void:
	if not _watching:
		return
	var started := Time.get_ticks_usec()
	_scheduler.run_all(_world, TICK)
	_tick_usec = lerpf(_tick_usec, Time.get_ticks_usec() - started, 0.05)

func _process(_delta: float) -> void:
	if _readout != null:
		_readout.text = "FPS %d   tick %.2f ms" % [Engine.get_frames_per_second(), _tick_usec / 1000.0]

## One town of `n` buildings and `count` villagers, run live with the camera on it.
func _watch(n: int, count: int) -> void:
	_town(n)
	# Roofs off, so the villagers show walking through the buildings.
	(_scheduler.systems()[6] as EcsTileSyncSystem).roofs_visible = false
	_spawn_villagers(count)
	for k in LOAD_TICKS:
		_scheduler.run_all(_world, TICK)
	_camera.position = _bounds.get_center()
	_camera.zoom = Vector2(0.5, 0.5)
	_watching = true
	var layer := CanvasLayer.new()
	add_child(layer)
	var ui := PanelContainer.new()
	ui.theme = preload("res://Global/Theme/main_theme.tres")
	ui.position = Vector2(12, 12)
	layer.add_child(ui)
	var box := VBoxContainer.new()
	ui.add_child(box)
	var what := Label.new()
	what.text = "%d buildings, %d villagers" % [n, count]
	box.add_child(what)
	_readout = Label.new()
	box.add_child(_readout)

func _measure(n: int, villagers: Array[int]) -> void:
	var started := Time.get_ticks_usec()
	var commands := _town(n)
	var plan_ms := (Time.get_ticks_usec() - started) / 1000.0
	var load := _ticks(LOAD_TICKS)
	var grid := _world.get_singleton(EcsTownGridSingleton) as EcsTownGridSingleton
	var build := _scheduler.systems()[1] as EcsBuildCommandSystem
	var rooms := 0
	for id in _world.query([EcsBuildingComponent]):
		rooms += (_world.get_component(id, EcsBuildingComponent) as EcsBuildingComponent).rooms.size()
	print("[stress] %d buildings, %d×%d cells: %d commands (%d refused), %d rooms, %d entities" % [
		n, grid.width, grid.height, commands, build.refused, rooms, _world.query([EcsPositionComponent]).size()])
	print("[stress]   load: plan %.0f ms, %d ticks %.0f ms (%s)" % [plan_ms, LOAD_TICKS, load.total / 1000.0, _stages(load.sums, 1000.0, "ms")])
	var had := 0
	for count in villagers:
		_spawn_villagers(count - had)
		had = count
		_ticks(2)
		var run := _ticks(MEASURE_TICKS)
		print("[stress]   %s %d villagers: tick %.0f µs avg, %d µs worst (%s)" % [
			"idle," if count == 0 else "with", count, float(run.total) / MEASURE_TICKS, run.worst,
			_stages(run.sums, float(MEASURE_TICKS), "µs")])
	_manager.clear()
	_root.free()

## A new world with `n` generated buildings queued as commands; returns how many commands.
func _town(n: int) -> int:
	var side := ceili(sqrt(n))
	var pitch := BUILDING + Vector2i(GAP, GAP)
	var cells := pitch * side + Vector2i(GAP, GAP)
	_bounds = Rect2(Vector2.ZERO, Vector2(cells * EcsTownGrid.CELL))
	var grid := EcsTownGrid.make(cells.x, cells.y, CATALOG.terrain_id(&"grass"))
	for k in n:
		var type: EcsBuildingTypeDef = CATALOG.building_types[k % CATALOG.building_types.size()]
		var at := Vector2i(k % side, k / side) * pitch + Vector2i(GAP, GAP)
		var plan := EcsBuildingGenerator.plan(type, BUILDING, RICH, FACINGS[k % 4], k, CATALOG, ENTITIES, at)
		grid.commands.append_array(plan.commands)
	var commands := grid.commands.size()
	_world = EcsWorld.new()
	_world.add_singleton(grid)
	_world.add_singleton(EcsLifecycleSingleton.new())
	_root = Node2D.new()
	add_child(_root)
	var layers := Node.new()
	_root.add_child(layers)
	var entities := Node2D.new()
	_root.add_child(entities)
	var overlay := EcsTownOverlay.new()
	_root.add_child(overlay)
	_manager = EcsEntityManager.new(entities)
	_scheduler = EcsScheduler.new()
	_scheduler \
		.add(EcsLifecycleSystem.new(_manager, ENTITIES)) \
		.add(EcsBuildCommandSystem.new(CATALOG, ENTITIES)) \
		.add(EcsRoomDetectionSystem.new(CATALOG)) \
		.add(EcsRoofSystem.new(CATALOG)) \
		.add(EcsWanderSystem.new(_bounds)) \
		.add(EcsMovementSystem.new()) \
		.add(EcsTileSyncSystem.new(layers, CATALOG)) \
		.add(EcsNodeSyncSystem.new(_manager)) \
		.add(EcsTownOverlaySystem.new(overlay))
	return commands

func _spawn_villagers(count: int) -> void:
	var inbox := _world.get_singleton(EcsLifecycleSingleton) as EcsLifecycleSingleton
	for k in count:
		var note := EcsSpawnRequest.new()
		note.type_id = &"villager"
		note.position = Vector2(randf_range(_bounds.position.x, _bounds.end.x), randf_range(_bounds.position.y, _bounds.end.y))
		inbox.spawn_requests.append(note)

## Runs `count` ticks, every stage every tick, timing each: {sums: {label: µs}, total, worst}.
func _ticks(count: int) -> Dictionary:
	var sums: Dictionary = {}
	var total := 0
	var worst := 0
	for t in count:
		var tick := 0
		for system in _scheduler.systems():
			var started := Time.get_ticks_usec()
			system.run(_world, TICK)
			var spent := Time.get_ticks_usec() - started
			sums[system.label()] = sums.get(system.label(), 0) + spent
			tick += spent
		total += tick
		worst = maxi(worst, tick)
	return {"sums": sums, "total": total, "worst": worst}

func _stages(sums: Dictionary, per: float, unit: String) -> String:
	var parts: PackedStringArray = []
	for label: StringName in sums:
		parts.append("%s %s" % [label, ("%.1f" if per > 1.0 and sums[label] / per < 10.0 else "%.0f") % (sums[label] / per)])
	return ", ".join(parts) + " " + unit
