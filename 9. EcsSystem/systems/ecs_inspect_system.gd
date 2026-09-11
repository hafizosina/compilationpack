class_name EcsInspectSystem
extends EcsSystem

## Builds the inspector's snapshot for whichever entity carries the selection
## tag, and pushes it onto the EventBus. The panel rebuilds from that dictionary
## and never touches the world.
##
## The snapshot is assembled by REFLECTION, and that is the interesting part.
## Module 8 needed every component to implement `describe()` — a method, on a
## component, written by hand, one per kind, kept in step with the fields it
## reported. Here a component is a field-only Resource, so its fields can simply
## be read off `get_property_list()`: `PROPERTY_USAGE_SCRIPT_VARIABLE` marks
## exactly the component's own declarations, exported and runtime alike, in the
## order they were written.
##
## So a new component kind gets an inspector tab, with its fields, in its
## declaration order, without this file or that component knowing anything about
## each other. Nothing here names a single component type.

## How often a snapshot is sent. The values are read by a person, so 5 Hz is
## plenty and costs nothing.
const INTERVAL: float = 0.2

var _since: float = 0.0
var _last_selected: int = EcsWorld.NO_ENTITY

func label() -> StringName:
	return &"inspect"

func run(world: EcsWorld, delta: float) -> void:
	var selected := world.query([EcsSelectedComponent])
	var id: int = selected[0] if not selected.is_empty() else EcsWorld.NO_ENTITY

	# A changed selection is sent at once; an unchanged one on the interval, so
	# clicking feels immediate without pushing a snapshot every frame.
	_since += delta
	if id == _last_selected and _since < INTERVAL:
		return
	_since = 0.0
	if id == EcsWorld.NO_ENTITY:
		if _last_selected != EcsWorld.NO_ENTITY:
			_last_selected = EcsWorld.NO_ENTITY
			EventBus.ecs_entity_inspected.emit({})
		return
	_last_selected = id
	EventBus.ecs_entity_inspected.emit(_snapshot(world, id))

func _snapshot(world: EcsWorld, id: int) -> Dictionary:
	var components := world.components_of(id)
	var keys := PackedStringArray()
	var sections: Dictionary = {}
	for component in components:
		keys.append(String(component.key()))
		sections[component.key()] = {
			"label": String(component.key()).capitalize(),
			"fields": _fields_of(world, component),
		}

	var named := world.get_component(id, EcsNameComponent) as EcsNameComponent
	return {
		"name": String(named.entity_name) if named != null else "#%d" % id,
		"type": String(named.type_id) if named != null else "—",
		"fields": {
			"id": "#%d" % id,
			"blueprint": named.display_name if named != null else "—",
			"components": ", ".join(keys),
		},
		"components": sections,
	}

## One component's own declarations, formatted. `PROPERTY_USAGE_SCRIPT_VARIABLE`
## keeps the script's own fields and drops everything Resource brings with it.
func _fields_of(world: EcsWorld, component: EcsComponent) -> Dictionary:
	var fields: Dictionary = {}
	for entry in component.get_property_list():
		if not (int(entry["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var property := String(entry["name"])
		if property.begins_with("_"):
			continue
		fields[property] = _format(world, property, component.get(property))
	return fields

func _format(world: EcsWorld, property: String, value: Variant) -> String:
	# An int field named *_id is a relationship. Showing the entity's name makes
	# "this monkey wields that dagger" legible without the reader tracking ids.
	if value is int and property.ends_with("_id") and world.is_alive(value):
		var named := world.get_component(value, EcsNameComponent) as EcsNameComponent
		return "#%d %s" % [value, named.entity_name if named != null else "?"]
	if value is float:
		return "%.2f" % value
	if value is Vector2:
		return "(%.0f, %.0f)" % [value.x, value.y]
	if value is Color:
		return "#" + (value as Color).to_html(false)
	if value is Resource:
		var path := (value as Resource).resource_path
		return path.get_file() if not path.is_empty() else "(built-in)"
	if value == null:
		return "—"
	return str(value)
