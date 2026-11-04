class_name EcsInspectSystem
extends EcsSystem

## Sends a snapshot of the first selected entity to the inspector over EventBus,
## with the ids of every selected one. Knows no component type: each component's
## `describe()` says how it reads, and one without it shows every field.
##
## Snapshot: `{name, type, ids, summary: {label: text}, bars: [{label, value, max,
## tone}], flags: [text], cards: [{key, label, enabled, lines: {label: text},
## fields: {field: {type, hint, hint_string, value}}}]}`. Cards are sorted by label.

## Seconds between snapshots.
const INTERVAL: float = 0.2
## Field types the inspector can edit.
const EDITABLE := [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME,
	TYPE_VECTOR2, TYPE_COLOR]

var _since: float = 0.0
var _last_selected: Array[int] = []

func label() -> StringName:
	return &"inspect"

func run(world: EcsWorld, delta: float) -> void:
	var selected := world.query([EcsSelectedFlag])
	selected.sort()

	# Send at once when the selection changes, otherwise on the interval.
	_since += delta
	if selected == _last_selected and _since < INTERVAL:
		return
	_since = 0.0
	if selected.is_empty():
		if not _last_selected.is_empty():
			_last_selected = []
			EventBus.ecs_entity_inspected.emit({})
		return
	_last_selected = selected
	var snapshot := _snapshot(world, selected[0])
	snapshot["ids"] = selected
	EventBus.ecs_entity_inspected.emit(snapshot)

func _snapshot(world: EcsWorld, id: int) -> Dictionary:
	var title := {"name": "#%d" % id, "type": "—"}
	var summary: Dictionary = {}
	var bars: Array = []
	var flags: Array = []
	var cards: Array = []
	for component in world.components_of(id):
		if component is EcsFlag:
			var text := _flag_name(component)
			var detail := _inline(world, component)
			flags.append(text if detail.is_empty() else "%s: %s" % [text, detail])
			continue
		var view := _present(world, component)
		if view.has("title"):
			title = view["title"]
		var lines: Dictionary = {}
		if component.enabled:
			match view.get("tab", &"own"):
				&"entity":
					summary.merge(view.get("lines", {}))
					bars.append_array(view.get("bars", []))
				&"own":
					lines = view.get("lines", {})
		cards.append({
			"key": component.key(),
			"label": String(component.key()).capitalize(),
			"enabled": component.enabled,
			"lines": lines,
			"fields": _editable_of(component),
		})
	cards.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["label"] < b["label"])
	flags.sort()
	return {
		"name": title.get("name", "#%d" % id),
		"type": title.get("type", "—"),
		"id": id,
		"summary": summary,
		"bars": bars,
		"flags": flags,
		"cards": cards,
	}

## The component's describe(), or its fields that can't be edited, as lines.
func _present(world: EcsWorld, component: EcsComponent) -> Dictionary:
	if component.has_method(&"describe"):
		return component.call(&"describe")
	var lines: Dictionary = {}
	var fields := _fields_of(world, component)
	var editable := _editable_of(component)
	for field in fields:
		if not editable.has(field):
			lines[field] = fields[field]
	return {"tab": &"own", "lines": lines}

## The component's script fields an inspector can edit, raw:
## `{field: {"type", "hint", "hint_string", "value"}}`. `enabled` is left to the
## card's own switch.
func _editable_of(component: EcsComponent) -> Dictionary:
	var fields: Dictionary = {}
	for entry in component.get_property_list():
		var property := String(entry["name"])
		if not (int(entry["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) or property.begins_with("_") \
				or property == "enabled" or not EDITABLE.has(int(entry["type"])):
			continue
		fields[property] = {
			"type": int(entry["type"]),
			"hint": int(entry["hint"]),
			"hint_string": String(entry["hint_string"]),
			"value": component.get(property),
		}
	return fields

## The component's own script fields, formatted.
func _fields_of(world: EcsWorld, component: EcsComponent) -> Dictionary:
	var fields: Dictionary = {}
	for entry in component.get_property_list():
		if not (int(entry["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var property := String(entry["name"])
		if property.begins_with("_") or property == "enabled":
			continue
		fields[property] = _format(world, property, component.get(property))
	return fields

## A flag's key, or its class name without "Ecs" and "Flag" when it has none.
func _flag_name(flag: EcsFlag) -> String:
	if flag.key() != &"":
		return String(flag.key()).capitalize()
	var script := flag.get_script() as Script
	var class_text := String(script.get_global_name()) if script != null else "Flag"
	return class_text.trim_prefix("Ecs").trim_suffix("Flag").capitalize()

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
	if value is Array:
		var items := value as Array
		if items.is_empty():
			return "—"
		if items.size() > 6:
			return "%d items" % items.size()
		var parts := PackedStringArray()
		for item in items:
			parts.append(_format(world, "", item))
		return ", ".join(parts)
	if value is Dictionary:
		return "%d entries" % (value as Dictionary).size()
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
