class_name SimEntityFactory
extends Node

## The spine. Reads a SimWorldDef placement list, looks each entry's blueprint up
## in a SimEntityCatalog, and assembles a live entity from that blueprint's
## component list.
##
## The factory is deliberately dumb: it never switches on component type, so a
## new component kind is a new SimComponentDef subclass and this file is
## untouched. Everything it produces is authored as .tres — no scene, no code.

const ENTITY_SCENE: PackedScene = preload("res://8. SimpleAiSystem/entity/sim_entity.tscn")

## Blueprint book to resolve `type` ids against.
@export var catalog: SimEntityCatalog
## Placement list describing what to spawn and where.
@export var world: SimWorldDef
## Node the spawned entities are parented to.
@export var entities_root: Node2D

## Group the factory joins so components can spawn without a hard node path.
const GROUP := &"sim_factory"

var _serial: int = 0

func _ready() -> void:
	add_to_group(GROUP)

## Clears any existing entities and spawns one entity per `world.entries` row.
func spawn_world() -> void:
	if catalog == null or world == null or entities_root == null:
		push_error("SimEntityFactory: catalog, world and entities_root must all be set")
		return
	clear()
	for placement in world.entries:
		if placement == null:
			continue
		spawn(placement.type, placement.position, placement.overrides, placement.entity_name)

## Builds one entity of `type_id` at `pos`. `overrides` is keyed by component
## slot, e.g. `{ "brain": { "wander_radius": 200.0 } }`.
func spawn(type_id: StringName, pos: Vector2, overrides: Dictionary = {}, entity_name: String = "") -> SimEntity:
	var blueprint := catalog.get_def(type_id)
	if blueprint == null:
		return null

	var entity: SimEntity = ENTITY_SCENE.instantiate()
	entity.def_id = type_id
	entity.name = entity_name if not entity_name.is_empty() else "%s_%d" % [type_id, _serial]
	entity.position = pos
	_serial += 1

	# Added to the tree BEFORE the components are built, so the entity's @onready
	# members (sprite, body) are resolved by the time build_into() touches them.
	entities_root.add_child(entity)

	for component_def in blueprint.components:
		if component_def == null:
			continue
		# Deep-duplicate per instance. Without this every entity of a type shares
		# one def object, and a single override silently rewrites all of them —
		# 30 entities behaving as 1 entity in 30 bodies.
		var instance_def: SimComponentDef = component_def.duplicate(true)
		var slot_overrides: Variant = _overrides_for(overrides, instance_def.slot())
		if slot_overrides is Dictionary:
			_apply_overrides(instance_def, slot_overrides)
		entity.remember_def(instance_def)
		instance_def.build_into(entity)

	if Constant.DEBUG:
		SimDebugComponent.attach(entity)

	return entity

## Frees every spawned entity. Safe to call before a respawn.
func clear() -> void:
	if entities_root == null:
		return
	for child in entities_root.get_children():
		# Detached first: queue_free() alone leaves the node parented until the
		# end of the frame, so a respawn in the same frame would double-count.
		entities_root.remove_child(child)
		child.queue_free()
	_serial = 0

## How many entities are alive right now.
func live_count() -> int:
	return 0 if entities_root == null else entities_root.get_child_count()

func _overrides_for(overrides: Dictionary, slot: StringName) -> Variant:
	if overrides.has(slot):
		return overrides[slot]
	return overrides.get(String(slot))

func _apply_overrides(component_def: SimComponentDef, overrides: Dictionary) -> void:
	for key in overrides:
		var property := StringName(key)
		if _has_property(component_def, property):
			component_def.set(property, overrides[key])
		else:
			push_warning("SimEntityFactory: slot '%s' has no property '%s' to override"
				% [component_def.slot(), property])

func _has_property(object: Object, property: StringName) -> bool:
	for entry in object.get_property_list():
		if entry.name == property:
			return true
	return false

## Prints one line per entity — its slots and their key tunables — so a leaked
## per-instance override is visible in the log as well as on screen.
func debug_report() -> void:
	if entities_root == null:
		return
	print("[sim] %d entities from %d entries"
		% [entities_root.get_child_count(), world.entries.size()])
	for child in entities_root.get_children():
		if not child is SimEntity:
			continue
		var entity: SimEntity = child
		var sensor := entity.get_component(&"sensor") as SimSensorComponent
		var movement := entity.get_component(&"movement") as SimMovementComponent
		print("[sim]   %-16s slots=%s sensor=%s walk=%s" % [
			entity.name,
			entity.component_slots(),
			"-" if sensor == null else str(sensor.radius),
			"-" if movement == null else str(movement.walk_speed),
		])
