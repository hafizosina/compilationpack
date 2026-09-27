class_name EcsInspectSystem
extends EcsSystem

## Builds the inspector's snapshot for whichever entity carries the selection
## tag, and pushes it onto the EventBus. The panel rebuilds from that dictionary
## and never touches the world.
##
## **It knows no component.** How a component reads is the component's own
## `describe()` — the one display-only method a component may have (see
## EcsComponent). This file knows only that contract, fixed once:
##
##     func describe() -> Dictionary
##         {"tab": &"entity" | &"own" | &"hidden",   # where it goes
##          "lines": {label: text},                  # what it says, in order
##          "title": {"name": ..., "type": ...}}     # optional: names the panel
##
## Changing how any component reads is an edit to that component's describe(),
## never to this file. A component without one gets its own tab with every
## field, read by REFLECTION off `get_property_list()` —
## `PROPERTY_USAGE_SCRIPT_VARIABLE` marks exactly its own declarations, in the
## order they were written. That fallback is generic, not a preference about
## any one kind.
##
## Flags are the one thing this lays out itself, and by base class alone: all of
## an entity's flags share one "Flags" tab, a line each.

## How often a snapshot is sent. The values are read by a person, so 5 Hz is
## plenty and costs nothing.
const INTERVAL: float = 0.2

var _since: float = 0.0
var _last_selected: int = EcsWorld.NO_ENTITY

func label() -> StringName:
	return &"inspect"

func run(world: EcsWorld, delta: float) -> void:
	var selected := world.query([EcsSelectedFlag])
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
	var keys := PackedStringArray()
	var sections: Dictionary = {}
	# Flags come and go, so they share one tab with a line each rather than
	# getting a tab apiece — a tab strip that grew and shrank every time an
	# intent was raised would be unreadable. The tab is always there, so it is
	# also where a flag is seen to be *absent*.
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

## What a component says about itself: its describe() if it has one, else its
## own tab with every field.
func _present(world: EcsWorld, component: EcsComponent) -> Dictionary:
	if component.has_method(&"describe"):
		return component.call(&"describe")
	return {"tab": &"own", "lines": _fields_of(world, component)}

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

## A flag's data on one line — `target #42 berry_7` — or empty for a flag whose
## presence is the whole of what it says.
func _inline(world: EcsWorld, flag: EcsFlag) -> String:
	var parts := PackedStringArray()
	var fields := _fields_of(world, flag)
	for field in fields:
		parts.append("%s %s" % [field, fields[field]])
	return ", ".join(parts)

func _format(world: EcsWorld, property: String, value: Variant) -> String:
	# An int field named *_id is a relationship. Showing the entity's name makes
	# "this monkey wields that dagger" legible without the reader tracking ids —
	# and the name is whatever title that entity's own components describe.
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

## The name an entity's components give it in describe(), or "?" if none do.
func _title_of(world: EcsWorld, id: int) -> String:
	for component in world.components_of(id):
		if component is EcsFlag:
			continue
		var view := _present(world, component)
		if view.has("title"):
			return str(view["title"].get("name", "?"))
	return "?"
