class_name EcsSnapshot
extends RefCounted

## Saves and loads a whole EcsWorld: every entity, component, flag and singleton,
## with ids kept as they were. Capturing only reads; EcsEntityManager rebuilds.
## Format and rules: HANDOFF.md §22.

const VERSION: int = 1
const SAVE_DIR := "user://saves/"
const EXTENSION := "ecs"
## Stored properties that are identity, not data.
const SKIPPED := ["resource_path", "resource_name", "resource_local_to_scene", "script"]

## Snapshots `world` into plain data, with no objects in it.
static func capture(world: EcsWorld) -> Dictionary:
	var ctx := {"objects": [], "seen": {}}
	var entities := {}
	for id: int in world.entity_ids():
		var held: Array = []
		for component in world.components_of(id):
			if component is EcsSelectedFlag:
				continue
			held.append(_encode(component, ctx))
		entities[id] = held
	var singletons: Array = []
	for singleton in world.singletons():
		if singleton is EcsSelectionSingleton or singleton is EcsEditSingleton \
				or singleton is EcsHealthSingleton:
			continue
		singletons.append(_encode(singleton, ctx))
	return {
		"version": VERSION,
		"next_id": world.next_id(),
		"objects": ctx["objects"],
		"entities": entities,
		"singletons": singletons,
	}

## Turns captured data back into live objects:
## `{ "next_id", "entities": { id: [EcsComponent] }, "singletons": [EcsComponent] }`.
## Empty if the data is not a snapshot this version can read.
static func decode(data: Dictionary) -> Dictionary:
	if int(data.get("version", -1)) != VERSION:
		push_error("EcsSnapshot: unsupported snapshot version %s" % data.get("version"))
		return {}
	var table: Array = data["objects"]
	var objects: Array = []
	for entry: Dictionary in table:
		if entry.has("$class"):
			objects.append(ClassDB.instantiate(entry["$class"]))
			continue
		var script := load(entry["$script"]) as Script
		objects.append(script.new() if script != null else null)
	# Fields after every object exists, so references and cycles resolve.
	for i in table.size():
		var target: Object = objects[i]
		if target == null:
			push_error("EcsSnapshot: cannot rebuild %s" % table[i].get("$script", table[i].get("$class")))
			continue
		var fields: Dictionary = table[i]["fields"]
		for field: String in fields:
			_set_field(target, field, _decode(fields[field], objects))

	var entities := {}
	for id in data["entities"]:
		var held: Array[EcsComponent] = []
		for value in data["entities"][id]:
			var component := _decode(value, objects) as EcsComponent
			if component != null:
				held.append(component)
		entities[int(id)] = held
	var singletons: Array[EcsComponent] = []
	for value in data["singletons"]:
		var singleton := _decode(value, objects) as EcsComponent
		if singleton != null:
			singletons.append(singleton)
	return {"next_id": int(data["next_id"]), "entities": entities, "singletons": singletons}

## Writes `data` to the save called `save_name`. Returns false on failure.
static func write(save_name: String, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var file := FileAccess.open(path_of(save_name), FileAccess.WRITE)
	if file == null:
		push_error("EcsSnapshot: cannot write %s (%s)" % [path_of(save_name), FileAccess.get_open_error()])
		return false
	file.store_string(var_to_str(data))
	return true

## Reads the save called `save_name`, or {} if it is missing or unreadable.
static func read(save_name: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path_of(save_name))
	if text.is_empty():
		push_error("EcsSnapshot: cannot read %s" % path_of(save_name))
		return {}
	var data: Variant = str_to_var(text)
	return data if data is Dictionary else {}

## Every save's name, sorted.
static func list_saves() -> PackedStringArray:
	var names := PackedStringArray()
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		return names
	for file in DirAccess.get_files_at(SAVE_DIR):
		if file.get_extension() == EXTENSION:
			names.append(file.get_basename())
	names.sort()
	return names

## Every save as `{name, time}`, newest first.
static func list_save_info() -> Array:
	var saves: Array = []
	for save_name in list_saves():
		saves.append({"name": save_name, "time": FileAccess.get_modified_time(path_of(save_name))})
	saves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["time"] > b["time"])
	return saves

## Deletes the save called `save_name`. True if it existed and is gone.
static func delete(save_name: String) -> bool:
	var path := path_of(save_name)
	return FileAccess.file_exists(path) and DirAccess.remove_absolute(path) == OK

static func path_of(save_name: String) -> String:
	return SAVE_DIR + save_name.validate_filename() + "." + EXTENSION

static func _encode(value: Variant, ctx: Dictionary) -> Variant:
	if value is Array:
		var out: Array = []
		for item in value:
			out.append(_encode(item, ctx))
		return out
	if value is Dictionary:
		var out := {}
		for key in value:
			out[_encode(key, ctx)] = _encode(value[key], ctx)
		return out
	if not (value is Object):
		return value
	var object: Object = value
	if object is Resource:
		var path := (object as Resource).resource_path
		if path != "" and not path.contains("::"):
			return {"$path": path}
	var seen: Dictionary = ctx["seen"]
	var key := object.get_instance_id()
	if seen.has(key):
		return {"$ref": seen[key]}
	var script := object.get_script() as Script
	var objects: Array = ctx["objects"]
	var index := objects.size()
	seen[key] = index
	# Scripted objects keep their script's fields; inline engine resources (a
	# GradientTexture2D in a blueprint) keep their class and stored properties.
	var entry := {"fields": {}}
	var usage := PROPERTY_USAGE_SCRIPT_VARIABLE
	if script != null:
		entry["$script"] = script.resource_path
	else:
		entry["$class"] = object.get_class()
		usage = PROPERTY_USAGE_STORAGE
	objects.append(entry)
	for property in object.get_property_list():
		if not (int(property["usage"]) & usage) or property["name"] in SKIPPED:
			continue
		entry["fields"][property["name"]] = _encode(object.get(property["name"]), ctx)
	return {"$ref": index}

static func _decode(value: Variant, objects: Array) -> Variant:
	if value is Array:
		var out: Array = []
		for item in value:
			out.append(_decode(item, objects))
		return out
	if value is Dictionary:
		if value.size() == 1 and value.has("$ref"):
			return objects[int(value["$ref"])]
		if value.size() == 1 and value.has("$path"):
			return load(value["$path"])
		var out := {}
		for key in value:
			out[_decode(key, objects)] = _decode(value[key], objects)
		return out
	return value

## Typed collections are filled in place so they keep their type.
static func _set_field(target: Object, field: String, value: Variant) -> void:
	var current: Variant = target.get(field)
	if current is Array and value is Array:
		(current as Array).assign(value)
	elif current is Dictionary and value is Dictionary:
		(current as Dictionary).assign(value)
	else:
		target.set(field, value)
