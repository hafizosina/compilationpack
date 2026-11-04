extends Node2D

## Module 9 entry point. Starts on a clean world with a start menu (open a map
## or a save, or start empty) and runs the system pipeline (see `_build()`) on
## every physics tick.
##
## Left-click selects an entity for the inspector, shift-click adds or removes
## one, and a left-drag box selects many; in place mode left-click places one
## (right-click or Escape stops). Space pauses, F1 toggles the debug overlay,
## F5 rebuilds the world, Delete removes the selection; the HUD does the same. Saves and composed
## blueprints live under user:// (HANDOFF.md §22, the HUD §24).

## Ticks between runs for sensor, planning, low_brain and danger (3 = 20 Hz).
const SLOW: int = 3

## Where composed blueprints are saved and loaded from.
const BLUEPRINT_DIR := "user://blueprints/"

## Ticks between runs for hunger, energy and thirst (6 = 10 Hz). Phases are chosen so no
## slow stages share a tick.
const BARS: int = 6

## Screen pixels a left press must travel to become a drag box.
const DRAG_PIXELS: float = 8.0

## Blueprint book to resolve placement `type` ids against.
@export var catalog: EcsEntityCatalog
## Maps the start menu offers, named by file.
@export var maps: Array[EcsWorldDef] = []
## Placement list to spawn; empty starts a clean world and opens the start menu.
@export var world_def: EcsWorldDef
## Playable area in global pixels; also the wander bounds.
@export var arena: Rect2 = Rect2(-3200.0, -1680.0, 6400.0, 3360.0)

@onready var _entities_root: Node2D = $World/Entities
@onready var _debug_overlay: EcsDebugOverlay = $World/DebugOverlay
@onready var _marker: EcsSelectionMarker = $World/SelectionMarker
@onready var _camera: Camera2D = $Camera2D

var _world: EcsWorld
var _scheduler: EcsScheduler
var _collision: EcsCollisionSystem
var _manager: EcsEntityManager
## Systems that still run while paused, so selection and the inspector work.
var _paused_systems: Array[EcsSystem] = []
var _paused: bool = false
## Built-in blueprints plus composed ones; `catalog` itself is never changed.
var _catalog: EcsEntityCatalog
## Blueprint placed on left-click, or empty.
var _place_type: StringName = &""
## True while a left press that may select is held.
var _pressing: bool = false
## Where that press began, in world and screen coordinates.
var _press_world: Vector2 = Vector2.ZERO
var _press_screen: Vector2 = Vector2.ZERO

func _ready() -> void:
	EcsConst.world_bounds = arena
	# The manager outlives each world, so it can free the old nodes on F5.
	_manager = EcsEntityManager.new(_entities_root)
	EventBus.ecs_respawn_requested.connect(_build)
	EventBus.ecs_save_requested.connect(_save)
	EventBus.ecs_load_requested.connect(_load)
	EventBus.ecs_place_type_chosen.connect(_on_place_type_chosen)
	EventBus.ecs_blueprint_saved.connect(_add_blueprint)
	EventBus.ecs_new_world_requested.connect(_on_new_world_requested)
	EventBus.ecs_entity_edit_requested.connect(_on_edit_requested)
	EventBus.ecs_entity_remove_requested.connect(_on_remove_requested)
	EventBus.ecs_pause_requested.connect(_toggle_pause)
	EventBus.ecs_overlay_toggle_requested.connect(_toggle_overlay)
	EventBus.ecs_entity_pick_requested.connect(_on_pick_requested)
	EventBus.ecs_camera_focus_requested.connect(_on_camera_focus_requested)
	EventBus.ecs_save_delete_requested.connect(_delete_save)
	EventBus.ecs_blueprint_delete_requested.connect(_delete_blueprint)
	_catalog = catalog.duplicate() as EcsEntityCatalog
	_catalog.defs = catalog.defs.duplicate()
	DirAccess.make_dir_recursive_absolute(BLUEPRINT_DIR)
	for file in DirAccess.get_files_at(BLUEPRINT_DIR):
		if file.get_extension() == "tres":
			_add_blueprint(BLUEPRINT_DIR + file, false)
	EventBus.ecs_catalog_changed.emit(_catalog.defs)
	EventBus.ecs_saves_changed.emit(EcsSnapshot.list_save_info())
	EventBus.ecs_overlay_changed.emit(_debug_overlay.visible)
	_build()
	if world_def == null:
		EventBus.ecs_start_menu_opened.emit(_map_names())

## Runs on the physics tick: a fixed timestep, and overlaps refresh once per tick.
func _physics_process(delta: float) -> void:
	if not _paused:
		_scheduler.run_all(_world, delta)
		return
	for system in _paused_systems:
		system.run(_world, delta)

## The end of a selecting press is read here, before the GUI, so a drag that ends
## over a panel still lands.
func _input(event: InputEvent) -> void:
	if not _pressing:
		return
	if event is InputEventMouseMotion:
		if _is_drag(event.position):
			_marker.show_box(Rect2(_press_world, Vector2.ZERO).expand(get_global_mouse_position()))
		return
	if event is InputEventMouseButton and not event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_pressing = false
		_marker.clear_box()
		# Resolved by EcsSelectionSystem next tick.
		var selection := _world.get_singleton(EcsSelectionSingleton) as EcsSelectionSingleton
		selection.pending = true
		selection.is_box = _is_drag(event.position)
		selection.pick_at = _press_world if selection.is_box else get_global_mouse_position()
		selection.drag_to = get_global_mouse_position()
		selection.additive = (event as InputEventMouseButton).shift_pressed

func _is_drag(screen_position: Vector2) -> bool:
	return screen_position.distance_to(_press_screen) > DRAG_PIXELS

func _unhandled_input(event: InputEvent) -> void:
	var stops_placing: bool = (event is InputEventMouseButton and event.pressed
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT) \
		or (event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE)
	if stops_placing and _place_type != &"":
		EventBus.ecs_place_type_chosen.emit(&"")
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and _place_type != &"":
		# Born at the next lifecycle stage, which also runs while paused.
		var note := EcsSpawnRequest.new()
		note.type_id = _place_type
		note.position = get_global_mouse_position()
		var inbox := _world.get_singleton(EcsLifecycleSingleton) as EcsLifecycleSingleton
		inbox.spawn_requests.append(note)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		# A click or a box; decided on release in _input().
		_pressing = true
		_press_world = get_global_mouse_position()
		_press_screen = (event as InputEventMouseButton).position
		get_viewport().set_input_as_handled()
		return

	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).keycode:
		KEY_F1:
			_toggle_overlay()
			get_viewport().set_input_as_handled()
		KEY_F5:
			_build()
			get_viewport().set_input_as_handled()
		KEY_SPACE:
			_toggle_pause()
			get_viewport().set_input_as_handled()
		KEY_DELETE:
			_on_remove_requested(_world.query([EcsSelectedFlag]))
			get_viewport().set_input_as_handled()

func _toggle_pause() -> void:
	_paused = not _paused
	EventBus.ecs_pause_changed.emit(_paused)

func _toggle_overlay() -> void:
	_debug_overlay.visible = not _debug_overlay.visible
	EventBus.ecs_overlay_changed.emit(_debug_overlay.visible)

## Builds a fresh world and the pipeline, from `world_def` or from a snapshot.
## The system order is the frame order.
func _build(snapshot: Dictionary = {}) -> void:
	if _collision != null:
		_collision.clear()
	_debug_overlay.clear()
	_marker.clear()
	EventBus.ecs_entity_inspected.emit({})

	_world = EcsWorld.new()
	_collision = EcsCollisionSystem.new(_manager)
	_scheduler = EcsScheduler.new()
	var lifecycle := EcsLifecycleSystem.new(_manager, _catalog)
	var edit := EcsEditSystem.new()
	var selection := EcsSelectionSystem.new(_marker)
	var node_sync := EcsNodeSyncSystem.new(_manager)
	var debug := EcsDebugSystem.new(_debug_overlay)
	var inspect := EcsInspectSystem.new()
	var census := EcsCensusSystem.new()
	var drop := EcsDropSystem.new()
	# Placing, inspecting, editing, removing and the outliner work while paused; nothing
	# simulates. Drop runs so a carrier removed while paused still leaves its bag.
	_paused_systems = [lifecycle, edit, drop, selection, node_sync, debug, census, inspect]

	_scheduler \
		.add(lifecycle) \
		.add(edit) \
		.add(EcsSpawnerSystem.new()) \
		.add(EcsHungerSystem.new(), BARS, 2) \
		.add(EcsEnergySystem.new(), BARS, 5) \
		.add(EcsThirstSystem.new(), BARS, 3) \
		.add(EcsDangerSystem.new(), SLOW, 1) \
		.add(EcsSensorSystem.new(_manager), SLOW, 0) \
		.add(EcsBreedingSystem.new(), SLOW, 0) \
		.add(EcsMemorySystem.new(), SLOW, 1) \
		.add(EcsPlanningSystem.new(), SLOW, 2) \
		.add(EcsLowBrainSystem.new(), SLOW, 1) \
		.add(EcsSkillSystem.new()) \
		.add(EcsConsumeSystem.new()) \
		.add(EcsDrinkSystem.new()) \
		.add(EcsHarvestSystem.new()) \
		.add(EcsAttackSystem.new()) \
		.add(EcsHealthSystem.new()) \
		.add(EcsMovementSystem.new()) \
		.add(_collision) \
		.add(EcsPickupSystem.new()) \
		.add(EcsRotSystem.new()) \
		.add(EcsCorpseSystem.new()) \
		.add(drop) \
		.add(selection) \
		.add(node_sync) \
		.add(debug) \
		.add(census) \
		.add(inspect)

	_world.add_singleton(EcsSelectionSingleton.new())
	_world.add_singleton(EcsEditSingleton.new())
	_world.add_singleton(EcsLifecycleSingleton.new())
	_world.add_singleton(EcsCombatSingleton.new())
	_world.add_singleton(EcsHealthSingleton.new())
	if snapshot.is_empty() or not _manager.load_snapshot(_world, snapshot):
		if world_def != null:
			_manager.spawn_world(_world, _catalog, world_def)
	EventBus.ecs_world_census.emit(_world.entity_count())
	if Constant.DEBUG and snapshot.is_empty() and world_def != null:
		_debug_report()

## Saves the whole world between ticks.
func _save(save_name: String) -> void:
	if save_name.strip_edges().is_empty():
		return
	if EcsSnapshot.write(save_name, EcsSnapshot.capture(_world)):
		EventBus.ecs_saves_changed.emit(EcsSnapshot.list_save_info())

func _delete_save(save_name: String) -> void:
	if EcsSnapshot.delete(save_name):
		EventBus.ecs_saves_changed.emit(EcsSnapshot.list_save_info())

## Replaces the world with a saved one; pause stays as it was.
func _load(save_name: String) -> void:
	var data := EcsSnapshot.read(save_name)
	if not data.is_empty():
		_build(data)

## Builds a fresh world from the map called `map_name`; empty builds an empty world.
func _on_new_world_requested(map_name: String) -> void:
	if map_name.is_empty():
		world_def = null
		_build()
		return
	var names := _map_names()
	var index := names.find(map_name)
	if index < 0:
		return
	world_def = maps[index]
	_build()

func _map_names() -> PackedStringArray:
	var names := PackedStringArray()
	for map in maps:
		names.append(map.resource_path.get_file().get_basename())
	return names

## Queues an inspector edit for EcsEditSystem's next run, which also runs while paused.
func _on_edit_requested(ids: Array, component: StringName, field: StringName, value: Variant) -> void:
	var edit := EcsEdit.new()
	edit.ids.assign(ids)
	edit.component = component
	edit.field = field
	edit.value = value
	(_world.get_singleton(EcsEditSingleton) as EcsEditSingleton).edits.append(edit)

## Selects `id` (toggles it, when `additive`) at EcsSelectionSystem's next run.
func _on_pick_requested(id: int, additive: bool) -> void:
	var selection := _world.get_singleton(EcsSelectionSingleton) as EcsSelectionSingleton
	selection.pending = true
	selection.pick_id = id
	selection.additive = additive

## Centres the camera on `id`. Only reads the world.
func _on_camera_focus_requested(id: int) -> void:
	if not _world.is_alive(id):
		return
	var place := _world.get_component(id, EcsPositionComponent) as EcsPositionComponent
	if place != null:
		_camera.global_position = place.position

## Queues `ids` for removal by EcsEditSystem, which also runs while paused.
func _on_remove_requested(ids: Array) -> void:
	(_world.get_singleton(EcsEditSingleton) as EcsEditSingleton).removals.append_array(ids)

func _on_place_type_chosen(type_id: StringName) -> void:
	_place_type = type_id if _catalog.has_def(type_id) else &""

## Deletes a composed blueprint's file and drops it from the runtime catalog.
## Built-in blueprints live in res:// and are never touched.
func _delete_blueprint(type_id: StringName) -> void:
	var def := _catalog.get_def(type_id)
	if def == null or not def.resource_path.begins_with(BLUEPRINT_DIR):
		return
	DirAccess.remove_absolute(def.resource_path)
	var defs: Array[EcsEntityDef] = []
	for kept in _catalog.defs:
		if kept.id != type_id:
			defs.append(kept)
	_catalog.defs = defs
	if _place_type == type_id:
		EventBus.ecs_place_type_chosen.emit(&"")
	EventBus.ecs_catalog_changed.emit(_catalog.defs)

## Adds or replaces a composed blueprint read from `path`.
func _add_blueprint(path: String, announce: bool = true) -> void:
	var def := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as EcsEntityDef
	if def == null or def.id == &"":
		push_warning("main: %s is not a blueprint" % path)
		return
	var defs: Array[EcsEntityDef] = []
	for kept in _catalog.defs:
		if kept.id != def.id:
			defs.append(kept)
	defs.append(def)
	_catalog.defs = defs
	if announce:
		EventBus.ecs_catalog_changed.emit(_catalog.defs)

## Prints what spawned, with each entity's speed.
func _debug_report() -> void:
	print("[ecs] %d entities from %d placements"
		% [_world.entity_count(), world_def.entries.size()])
	for id in _world.query([EcsNameComponent]):
		var named := _world.get_component(id, EcsNameComponent) as EcsNameComponent
		var move := _world.get_component(id, EcsMovementComponent) as EcsMovementComponent
		print("[ecs]   #%-3d %-12s %-9s speed %s"
			% [id, named.entity_name, named.type_id, move.speed if move != null else "-"])
