extends Node2D

## Module 9 entry point. Builds the world from world1.tres and runs the system
## pipeline (see `_build()`) on every physics tick.
##
## Left-click selects an entity for the inspector. F1 toggles the debug overlay,
## F5 rebuilds the world from data.

## Ticks between runs for sensor, planning, low_brain, danger and health (3 = 20 Hz).
const SLOW: int = 3

## Ticks between runs for hunger, energy and thirst (6 = 10 Hz). Phases are chosen so no
## slow stages share a tick.
const BARS: int = 6

## Blueprint book to resolve placement `type` ids against.
@export var catalog: EcsEntityCatalog
## Placement list describing what to spawn and where.
@export var world_def: EcsWorldDef
## Playable area in global pixels; also the wander bounds.
@export var arena: Rect2 = Rect2(-3200.0, -1680.0, 6400.0, 3360.0)

@onready var _entities_root: Node2D = $World/Entities
@onready var _debug_overlay: EcsDebugOverlay = $World/DebugOverlay
@onready var _marker: EcsSelectionMarker = $World/SelectionMarker

var _world: EcsWorld
var _scheduler: EcsScheduler
var _collision: EcsCollisionSystem
var _manager: EcsEntityManager

func _ready() -> void:
	EcsConst.world_bounds = arena
	# The manager outlives each world, so it can free the old nodes on F5.
	_manager = EcsEntityManager.new(_entities_root)
	EventBus.ecs_respawn_requested.connect(_build)
	_build()

## Runs on the physics tick: a fixed timestep, and overlaps refresh once per tick.
func _physics_process(delta: float) -> void:
	_scheduler.run_all(_world, delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		# Resolved by EcsSelectionSystem next tick.
		var selection := _world.get_singleton(EcsSelectionSingleton) as EcsSelectionSingleton
		selection.pending = true
		selection.pick_at = get_global_mouse_position()
		get_viewport().set_input_as_handled()
		return

	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).keycode:
		KEY_F1:
			_debug_overlay.visible = not _debug_overlay.visible
			get_viewport().set_input_as_handled()
		KEY_F5:
			_build()
			get_viewport().set_input_as_handled()

## Builds a fresh world and the pipeline. The system order is the frame order.
func _build() -> void:
	if _collision != null:
		_collision.clear()
	_debug_overlay.clear()
	_marker.clear()
	EventBus.ecs_entity_inspected.emit({})

	_world = EcsWorld.new()
	_collision = EcsCollisionSystem.new(_manager)
	_scheduler = EcsScheduler.new()

	_scheduler \
		.add(EcsLifecycleSystem.new(_manager, catalog)) \
		.add(EcsSpawnerSystem.new()) \
		.add(EcsHungerSystem.new(), BARS, 2) \
		.add(EcsEnergySystem.new(), BARS, 5) \
		.add(EcsThirstSystem.new(), BARS, 3) \
		.add(EcsHealthSystem.new(), SLOW, 2) \
		.add(EcsDangerSystem.new(), SLOW, 1) \
		.add(EcsSensorSystem.new(_manager), SLOW, 0) \
		.add(EcsPlanningSystem.new(), SLOW, 2) \
		.add(EcsLowBrainSystem.new(), SLOW, 1) \
		.add(EcsSkillSystem.new()) \
		.add(EcsConsumeSystem.new()) \
		.add(EcsDrinkSystem.new()) \
		.add(EcsHarvestSystem.new()) \
		.add(EcsAttackSystem.new()) \
		.add(EcsCritSystem.new()) \
		.add(EcsDamageSystem.new()) \
		.add(EcsMovementSystem.new()) \
		.add(_collision) \
		.add(EcsPickupSystem.new()) \
		.add(EcsRotSystem.new()) \
		.add(EcsCorpseSystem.new()) \
		.add(EcsDropSystem.new()) \
		.add(EcsSelectionSystem.new(_marker)) \
		.add(EcsNodeSyncSystem.new(_manager)) \
		.add(EcsDebugSystem.new(_debug_overlay)) \
		.add(EcsCensusSystem.new()) \
		.add(EcsInspectSystem.new())

	_world.add_singleton(EcsSelectionSingleton.new())
	_world.add_singleton(EcsLifecycleSingleton.new())
	_world.add_singleton(EcsCombatSingleton.new())
	_manager.spawn_world(_world, catalog, world_def)
	EventBus.ecs_world_census.emit(_world.entity_count())
	if Constant.DEBUG:
		_debug_report()

## Prints what spawned, with each entity's speed.
func _debug_report() -> void:
	print("[ecs] %d entities from %d placements"
		% [_world.entity_count(), world_def.entries.size()])
	for id in _world.query([EcsNameComponent]):
		var named := _world.get_component(id, EcsNameComponent) as EcsNameComponent
		var move := _world.get_component(id, EcsMovementComponent) as EcsMovementComponent
		print("[ecs]   #%-3d %-12s %-9s speed %s"
			% [id, named.entity_name, named.type_id, move.speed if move != null else "-"])
