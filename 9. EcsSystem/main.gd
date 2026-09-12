extends Node2D

## Module 9 entry point — a hand-rolled ECS, stripped to the smallest thing that
## still runs, so the shape of a frame is readable end to end.
##
## Everything on screen is a row in an EcsWorld: an entity is an integer id, a
## component is a field-only Resource, and every behaviour is an EcsSystem that
## queries for the components it cares about. The Sprite2Ds under World/Entities
## are views the render system writes, not the entities themselves.
##
## The whole flow, in the order it happens:
##
##   world1.tres  ──►  EcsEntityFactory  ──►  EcsWorld       (once, at startup)
##   (placements)      (resolves each row     (ids + component
##                      against catalog.tres)  tables)
##
##   every frame, EcsScheduler runs three systems over that world:
##
##     low_brain  picks a destination  → writes EcsMovementComponent
##     movement   walks toward it      → writes EcsPositionComponent
##     collision  unstacks the bodies  → writes EcsPositionComponent
##                (Area2D pool under World/Bodies is a derived index only)
##     render     draws where it ended → writes Sprite2D nodes
##     debug      reports all of it    → writes the on-entity overlay
##
## Read those four files in that order and you have seen the whole module. The
## debug system is a pure reader: pull it out and nothing else notices.
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

var _world: EcsWorld
var _scheduler: EcsScheduler
var _render: EcsRenderSystem
var _collision: EcsCollisionSystem
var _factory := EcsEntityFactory.new()

func _ready() -> void:
	EcsConst.world_bounds = arena
	_build()

## The pipeline runs on the physics tick, not the render frame. Two reasons:
## a simulation wants a fixed timestep, and EcsCollisionSystem reads overlaps
## the physics server refreshes once per tick — running faster than that would
## just re-read the same answer.
func _physics_process(delta: float) -> void:
	_scheduler.run_all(_world, delta)

func _unhandled_input(event: InputEvent) -> void:
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

	_world = EcsWorld.new()
	_render = EcsRenderSystem.new(_entities_root)
	_collision = EcsCollisionSystem.new(_bodies_root)
	_scheduler = EcsScheduler.new()

	_scheduler \
		.add(EcsLowBrainSystem.new()) \
		.add(EcsMovementSystem.new()) \
		.add(_collision) \
		.add(_render) \
		.add(EcsDebugSystem.new(_debug_overlay))

	_factory.spawn_world(_world, catalog, world_def)
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
