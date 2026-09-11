extends Node2D

## Module 9 entry point — the hand-rolled ECS rewrite of module 8's foundation.
##
## Everything on screen is a row in an EcsWorld: an entity is an integer id, a
## component is a field-only Resource, and every behaviour is an EcsSystem that
## queries for the components it cares about. The Sprite2Ds under World/Entities
## and the selection marker beside them are views the systems write, not the
## entities themselves.
##
## The whole world comes out of world1.tres, so edit the .tres, press F5, and
## watch the change without touching code.
##
## Left-click an entity to inspect it in the bottom-left panel; the selected
## entity also shows the reach it can strike within. Click bare ground to clear.
##
## Keys:
##   F2  toggle the crit system in and out of the pipeline
##   F3  give the crocodile an armour component, or take it away
##   F5  rebuild the world from data
##
## F2 and F3 are the acceptance test made pressable. Neither the attack system
## nor the damage system was written knowing that crits or armour exist; one is
## a system spliced into the run order, the other a component filed against an
## entity, and both change the outcome of a fight without either file changing.
##
## This node owns the world, the scheduler and the views, and that is all it
## does. It reads no component and writes none: a click becomes a request on the
## selection singleton, a debug key becomes a request on the commands singleton,
## and a system resolves each next frame.

## Blueprint book to resolve placement `type` ids against.
@export var catalog: EcsEntityCatalog
## Placement list describing what to spawn and where.
@export var world_def: EcsWorldDef
## Playable extents, in global pixels. Adopted as the wander bounds at startup,
## so moving the ground plate moves where things drift.
@export var arena: Rect2 = Rect2(-800.0, -420.0, 1600.0, 840.0)
## Entity the F3 armour demo toggles its component on.
@export var armour_demo_target: StringName = &"crocodile_0"

@onready var _entities_root: Node2D = $World/Entities
@onready var _marker: EcsSelectionMarker = $World/SelectionMarker

var _world: EcsWorld
var _scheduler: EcsScheduler
var _render: EcsRenderSystem
var _factory := EcsEntityFactory.new()

func _ready() -> void:
	EcsConst.world_bounds = arena
	EventBus.ecs_respawn_requested.connect(_build)
	_build()

func _process(delta: float) -> void:
	_scheduler.run_all(_world, delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var selection := _world.get_singleton(EcsSelectionComponent) as EcsSelectionComponent
		selection.pending = true
		selection.pick_at = get_global_mouse_position()
		get_viewport().set_input_as_handled()
		return

	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).keycode:
		KEY_F2:
			var crit := _scheduler.find(&"crit")
			if crit != null:
				crit.enabled = not crit.enabled
				_report_pipeline()
			get_viewport().set_input_as_handled()
		KEY_F3:
			_queue_toggle(armour_demo_target, EcsArmorComponent.new())
			get_viewport().set_input_as_handled()
		KEY_F5:
			_build()
			get_viewport().set_input_as_handled()

## Builds a fresh world and the pipeline that runs it. The scheduler's order is
## the whole story of a frame, which is why it is one readable chain: decide,
## then act, then resolve the consequences, then draw the result.
func _build() -> void:
	if _render != null:
		_render.clear()
	_marker.clear()
	EventBus.ecs_entity_inspected.emit({})

	_world = EcsWorld.new()
	_world.add_singleton(EcsCommandsComponent.new())
	_world.add_singleton(EcsSelectionComponent.new())
	_render = EcsRenderSystem.new(_entities_root)
	_scheduler = EcsScheduler.new()

	_scheduler \
		.add(EcsCommandSystem.new()) \
		.add(EcsEquipSystem.new()) \
		.add(EcsWanderSystem.new()) \
		.add(EcsMovementSystem.new()) \
		.add(EcsWeaponCarrySystem.new()) \
		.add(EcsAggressionSystem.new()) \
		.add(EcsAttackSystem.new()) \
		.add(EcsCritSystem.new()) \
		.add(EcsDamageSystem.new()) \
		.add(EcsDurabilitySystem.new()) \
		.add(EcsDeathSystem.new()) \
		.add(EcsSelectionSystem.new(_marker)) \
		.add(_render) \
		.add(EcsCensusSystem.new()) \
		.add(EcsInspectSystem.new())

	_factory.spawn_world(_world, catalog, world_def)
	_report_pipeline()
	EventBus.ecs_world_census.emit(_world.entity_count())
	if Constant.DEBUG:
		_debug_report()

## Queues a component toggle for EcsCommandSystem to apply next frame. Input
## handlers go through the queue rather than writing components directly, so the
## rule that only systems mutate component data holds even for the debug keys.
func _queue_toggle(target_name: StringName, component: EcsComponent) -> void:
	var commands := _world.get_singleton(EcsCommandsComponent) as EcsCommandsComponent
	if commands == null:
		return
	commands.queued.append({ "target_name": target_name, "component": component })

## Pushes the run order to the panel, disabled stages in brackets. This node
## owns the scheduler, so it is the one thing that can honestly report it.
func _report_pipeline() -> void:
	var parts := PackedStringArray()
	for system in _scheduler.systems():
		parts.append(String(system.label()) if system.enabled else "(%s)" % system.label())
	EventBus.ecs_pipeline_changed.emit(" > ".join(parts))

func _debug_report() -> void:
	print("[ecs] %d entities from %d placements"
		% [_world.entity_count(), world_def.entries.size()])
	for id in _world.query([EcsNameComponent]):
		var named := _world.get_component(id, EcsNameComponent) as EcsNameComponent
		print("[ecs]   #%-3d %-14s %s" % [id, named.entity_name, named.type_id])
