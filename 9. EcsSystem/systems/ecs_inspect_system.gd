class_name EcsInspectSystem
extends EcsSystem

## Sends a snapshot of the selected entity to the inspector over EventBus.
## Knows no component type: each component's `describe()` says how it shows,
## and one without it shows every field. Flags share one tab.

## Seconds between snapshots.
const INTERVAL: float = 0.2

var _since: float = 0.0
var _last_selected: int = EcsWorld.NO_ENTITY

func label() -> StringName:
	return &"inspect"

func run(world: EcsWorld, delta: float) -> void:
	var selected := world.query([EcsSelectedFlag])
	var id: int = selected[0] if not selected.is_empty() else EcsWorld.NO_ENTITY

	# Send at once when the selection changes, otherwise on the interval.
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
	var keys := PackedStringArray()
	var sections: Dictionary = {}
	var flags: Dictionary = {}
	var entity_lines: Dictionary = {}
	var title := {"name": "#%d" % id, "type": "—"}
	for component in world.components_of(id):
		if component is EcsFlag:
			flags[String(component.key()).capitalize()] = _inline(world, component)
			continue
		keys.append(String(component.key()))
		var view := _present(world, component)
		if view.has("title"):
			title = view["title"]
		match view.get("tab", &"own"):
			&"hidden":
				pass
			&"entity":
				entity_lines.merge(view.get("lines", {}))
			_:
				sections[component.key()] = {
					"label": String(component.key()).capitalize(),
					"fields": view.get("lines", {}),
				}
	sections[&"flags"] = {
		"label": "Flags",
		"fields": flags if not flags.is_empty() else {"none": ""},
	}

	entity_lines["id"] = "#%d" % id
	entity_lines["components"] = ", ".join(keys)
	return {
		"name": title.get("name", "#%d" % id),
		"type": title.get("type", "—"),
		"fields": entity_lines,
		"components": sections,
	}

## The component's describe(), or a tab of all its fields.
func _present(world: EcsWorld, component: EcsComponent) -> Dictionary:
	if component.has_method(&"describe"):
		return component.call(&"describe")
	return {"tab": &"own", "lines": _fields_of(world, component)}

## The component's own script fields, formatted.
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

## A flag's fields on one line, or empty.
func _inline(world: EcsWorld, flag: EcsFlag) -> String:
	var parts := PackedStringArray()
	var fields := _fields_of(world, flag)
	for field in fields:
		parts.append("%s %s" % [field, fields[field]])
	return ", ".join(parts)

func _format(world: EcsWorld, property: String, value: Variant) -> String:
	# An int field ending in _id is shown with the entity's name.
	if value is int and property.ends_with("_id") and world.is_alive(value):
		return "#%d %s" % [value, _title_of(world, value)]
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

## The entity's title from describe(), or "?".
func _title_of(world: EcsWorld, id: int) -> String:
	for component in world.components_of(id):
		if component is EcsFlag:
			continue
		var view := _present(world, component)
		if view.has("title"):
			return str(view["title"].get("name", "?"))
	return "?"
