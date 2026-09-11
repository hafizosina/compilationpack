class_name EcsEntityFactory
extends RefCounted

## Reads a placement list, resolves each row's blueprint and files that
## blueprint's components against a fresh entity id.
##
## Compare with the node-composition factory it replaces: that one instantiated
## a scene, added it to the tree so @onready members would resolve, then asked
## every component def to build a node into it. This one has no scene, no tree
## and no build step — spawning is create an id, copy the data, done. The
## factory got smaller because the components stopped being nodes.
##
## It stays deliberately dumb in the same way, though: it never switches on
## component type, so a new component kind is a new EcsComponent subclass and
## this file is untouched.

var _serial: int = 0

## Clears the world and spawns one entity per `world_def.entries` row.
func spawn_world(world: EcsWorld, catalog: EcsEntityCatalog, world_def: EcsWorldDef) -> void:
	if world == null or catalog == null or world_def == null:
		push_error("EcsEntityFactory: world, catalog and world_def must all be set")
		return
	_serial = 0
	for placement in world_def.entries:
		if placement == null:
			continue
		spawn(world, catalog, placement.type, placement.position,
			placement.overrides, placement.entity_name)

## Builds one entity of `type_id` at `pos` and returns its id, or NO_ENTITY.
## `overrides` is keyed by component key, e.g. `{ "wander": { "radius": 200.0 } }`.
func spawn(world: EcsWorld, catalog: EcsEntityCatalog, type_id: StringName, pos: Vector2,
		overrides: Dictionary = {}, entity_name: StringName = &"") -> int:
	var blueprint := catalog.get_def(type_id)
	if blueprint == null:
		return EcsWorld.NO_ENTITY

	var id := world.create_entity()

	# Identity and place come from the placement rather than the blueprint —
	# every entity has both, and neither is a property of its type.
	var named := EcsNameComponent.new()
	named.entity_name = entity_name if entity_name != &"" else StringName("%s_%d" % [type_id, _serial])
	named.type_id = type_id
	named.display_name = blueprint.display_name
	world.add(id, named)
	var position := EcsPositionComponent.new()
	position.position = pos
	world.add(id, position)
	_serial += 1

	for template in blueprint.components:
		if template == null:
			continue
		# Deep-copied per instance. Without this every entity of a type shares
		# one component object and a single override silently rewrites all of
		# them — thirty entities behaving as one entity in thirty bodies.
		var component: EcsComponent = template.duplicate(true)
		var slot_overrides: Variant = _overrides_for(overrides, component.key())
		if slot_overrides is Dictionary:
			_apply_overrides(component, slot_overrides)
		world.add(id, component)

	return id

func _overrides_for(overrides: Dictionary, component_key: StringName) -> Variant:
	if overrides.has(component_key):
		return overrides[component_key]
	return overrides.get(String(component_key))

func _apply_overrides(component: EcsComponent, overrides: Dictionary) -> void:
	for name_key in overrides:
		var property := StringName(name_key)
		if _has_property(component, property):
			component.set(property, overrides[name_key])
		else:
			push_warning("EcsEntityFactory: component '%s' has no property '%s' to override"
				% [component.key(), property])

func _has_property(object: Object, property: StringName) -> bool:
	for entry in object.get_property_list():
		if entry.name == property:
			return true
	return false
