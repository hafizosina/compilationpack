extends Node2D

## Module 9 entry point — a hand-rolled ECS, stripped to the smallest thing that
## still runs, so the shape of a frame is readable end to end.
##
## Everything on screen is a row in an EcsWorld: an entity is an integer id, a
## component is a field-only Resource, and every behaviour is an EcsSystem that
## queries for the components it cares about. The Sprite2Ds under World/Entities
## and the ring beside them are views the systems write, not the entities.
##
## Left-click an entity to inspect it in the bottom-left panel; click bare
## ground to clear. A click is not handled here beyond being written to the
## selection singleton — a system resolves it on the next tick, so the rule that
## only a system reads the world and writes components holds for input too.
##
## The whole flow, in the order it happens:
##
##   world1.tres  ──►  EcsEntityFactory  ──►  EcsWorld       (once, at startup)
##   (placements)      (resolves each row     (ids + component
##                      against catalog.tres)  tables)
##
##   every tick, EcsScheduler runs these systems over that world, in order:
##
##     spawner    adds new entities    → creates ids, files components
##     forage     go get a berry       → writes EcsMovementComponent
##     low_brain  else wander          → writes EcsMovementComponent
##     movement   walks toward it      → writes EcsPositionComponent
##     collision  unstacks the bodies  → writes EcsPositionComponent
##                (Area2D pool under World/Bodies is a derived index only)
##     selection  resolves a click     → writes EcsSelectedComponent
##     render     draws where it ended → writes Sprite2D nodes
##     debug      reports all of it    → writes the on-entity overlay
##     census     counts the world     → emits on the EventBus
##     inspect    reflects the selected → emits on the EventBus
##
## Read low_brain, movement and render in that order and you have seen every
## behaviour. The last three stages are pure readers: pull debug, census or
## inspect out of the chain and the simulation does not notice.
##
## Keys:
##   F1  show/hide the on-entity debug overlay
##   F5  rebuild the world from data — edit world1.tres or a blueprint,
##       press F5, and see the change with no code touched.

## Blueprint book to resolve placement `type` ids against.
@export var catalog: EcsEntityCatalog
## Placement list describing what to spawn and where.
@export var world_def: EcsWorldDef
## Playable extents, in global pixels. Adopted as the wander bounds at startup,
## so moving the ground plate moves where things drift.
@export var arena: Rect2 = Rect2(-1600.0, -840.0, 3200.0, 1680.0)

@onready var _entities_root: Node2D = $World/Entities
@onready var _bodies_root: Node2D = $World/Bodies
@onready var _debug_overlay: EcsDebugOverlay = $World/DebugOverlay
@onready var _marker: EcsSelectionMarker = $World/SelectionMarker

var _world: EcsWorld
var _scheduler: EcsScheduler
var _render: EcsRenderSystem
var _collision: EcsCollisionSystem
var _factory := EcsEntityFactory.new()

func _ready() -> void:
	EcsConst.world_bounds = arena
	EventBus.ecs_respawn_requested.connect(_build)
	_build()

## The pipeline runs on the physics tick, not the render frame. Two reasons:
## a simulation wants a fixed timestep, and EcsCollisionSystem reads overlaps
## the physics server refreshes once per tick — running faster than that would
## just re-read the same answer.
func _physics_process(delta: float) -> void:
	_scheduler.run_all(_world, delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		# Recorded, not resolved. EcsSelectionSystem drains this next tick.
		var selection := _world.get_singleton(EcsSelectionComponent) as EcsSelectionComponent
		selection.pending = true
		selection.pick_at = get_global_mouse_position()
		get_viewport().set_input_as_handled()
		return

	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).keycode:
		KEY_F1:
			# Visibility is view state, not component data, so this is the one
			# thing a key may change directly.
			_debug_overlay.visible = not _debug_overlay.visible
			get_viewport().set_input_as_handled()
		KEY_F5:
			_build()
			get_viewport().set_input_as_handled()

## Builds a fresh world and the pipeline that runs it. The scheduler's order is
## the whole story of a frame, which is why it is one readable chain: decide
## where to go, then go there, then fix up where that actually left everyone,
## then draw the result. The first stage is named for
## its rank, not its behaviour: a smarter brain later takes EcsLowBrainSystem's
## place and writes the same destination field.
func _build() -> void:
	if _render != null:
		_render.clear()
	if _collision != null:
		_collision.clear()
	_debug_overlay.clear()
	_marker.clear()
	EventBus.ecs_entity_inspected.emit({})

	_world = EcsWorld.new()
	_render = EcsRenderSystem.new(_entities_root)
	_collision = EcsCollisionSystem.new(_bodies_root)
	_scheduler = EcsScheduler.new()

	_scheduler \
		.add(EcsSpawnerSystem.new(_factory, catalog)) \
		.add(EcsForageSystem.new()) \
		.add(EcsLowBrainSystem.new()) \
		.add(EcsMovementSystem.new()) \
		.add(_collision) \
		.add(EcsPickupSystem.new()) \
		.add(EcsSelectionSystem.new(_marker)) \
		.add(_render) \
		.add(EcsDebugSystem.new(_debug_overlay)) \
		.add(EcsCensusSystem.new()) \
		.add(EcsInspectSystem.new())

	_world.add_singleton(EcsSelectionComponent.new())
	_factory.spawn_world(_world, catalog, world_def)
	EventBus.ecs_world_census.emit(_world.entity_count())
	if Constant.DEBUG:
		_debug_report()

## Prints what spawned. Speed is shown because it is authored in two places —
## the blueprint, and a placement override on one entity — so the listing makes
## the per-instance copy visible without opening the .tres.
func _debug_report() -> void:
	print("[ecs] %d entities from %d placements"
		% [_world.entity_count(), world_def.entries.size()])
	for id in _world.query([EcsNameComponent]):
		var named := _world.get_component(id, EcsNameComponent) as EcsNameComponent
		var move := _world.get_component(id, EcsMovementComponent) as EcsMovementComponent
		print("[ecs]   #%-3d %-12s %-9s speed %s"
			% [id, named.entity_name, named.type_id, move.speed if move != null else "-"])
