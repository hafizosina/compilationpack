class_name EcsWorld
extends RefCounted

## Entity ids, component storage and queries. An entity is just an int.
## Storage is `{ Script : { entity_id : EcsComponent } }`, one table per type.

## Id 0 means "no entity".
const NO_ENTITY: int = 0

var _next_id: int = 1
var _alive: Dictionary = {}  # entity_id -> true
var _store: Dictionary = {}  # Script -> { entity_id -> EcsComponent }
var _singletons: Dictionary = {}  # Script -> EcsComponent
## Script -> int, bumped whenever that table gains, loses or replaces an entry.
var _versions: Dictionary = {}
## [include, exclude] -> EcsView.
var _views: Dictionary = {}

# --- entities ---------------------------------------------------------------

func create_entity() -> int:
	var id := _next_id
	_next_id += 1
	_alive[id] = true
	return id

## Removes the entity and all its components. Ids are never reused.
func destroy_entity(id: int) -> void:
	if not _alive.erase(id):
		return
	for type: Script in _store:
		if (_store[type] as Dictionary).erase(id):
			_versions[type] = int(_versions.get(type, 0)) + 1

## Recreates entity `id` when loading a snapshot. False if it is already alive.
func create_entity_with_id(id: int) -> bool:
	if id == NO_ENTITY or _alive.has(id):
		return false
	_alive[id] = true
	_next_id = maxi(_next_id, id + 1)
	return true

## The id the next new entity will get.
func next_id() -> int:
	return _next_id

## Raises the next id to at least `id`, so a loaded world never reuses one.
func reserve_ids_below(id: int) -> void:
	_next_id = maxi(_next_id, id)

## Every live entity id.
func entity_ids() -> Array:
	return _alive.keys()

func is_alive(id: int) -> bool:
	return _alive.has(id)

func entity_count() -> int:
	return _alive.size()

# --- components -------------------------------------------------------------

## Adds `component` to `id`, replacing any component of the same type.
func add(id: int, component: EcsComponent) -> EcsComponent:
	if component == null:
		push_error("EcsWorld: cannot add a null component to entity %d" % id)
		return null
	if not _alive.has(id):
		push_error("EcsWorld: entity %d is not alive; component dropped" % id)
		return null
	var type: Script = component.get_script()
	if not _store.has(type):
		_store[type] = {}
	_store[type][id] = component
	# Bumped on replace too, so views drop the old reference.
	_versions[type] = int(_versions.get(type, 0)) + 1
	return component

func get_component(id: int, type: Script) -> EcsComponent:
	var table: Dictionary = _store.get(type, {})
	return table.get(id)

func has(id: int, type: Script) -> bool:
	var table: Dictionary = _store.get(type, {})
	return table.has(id)

func remove(id: int, type: Script) -> void:
	var table: Dictionary = _store.get(type)
	if table != null and table.erase(id):
		_versions[type] = int(_versions.get(type, 0)) + 1

## Cached `query(include, exclude)` with component columns (see EcsView).
## Returns the same view until a table it names changes. Avoid naming types
## that change every tick; the rebuild costs more than a plain query.
func view(include: Array, exclude: Array = []) -> EcsView:
	var key := [include, exclude]
	var cached: EcsView = _views.get(key)
	if cached != null and _is_current(cached):
		return cached

	var fresh := EcsView.new()
	fresh.ids = query(include, exclude)
	for type: Script in include:
		var table: Dictionary = _store.get(type, {})
		var column: Array = []
		column.resize(fresh.ids.size())
		for k in fresh.ids.size():
			column[k] = table[fresh.ids[k]]
		fresh._columns[type] = column
	for type: Script in include + exclude:
		fresh._types.append(type)
		fresh._stamp.append(int(_versions.get(type, 0)))
	_views[key] = fresh
	return fresh

func _is_current(cached: EcsView) -> bool:
	for k in cached._types.size():
		if int(_versions.get(cached._types[k], 0)) != cached._stamp[k]:
			return false
	return true

## Every entity with all of `include` and none of `exclude`, as a new array.
## Scans the smallest included table.
func query(include: Array, exclude: Array = []) -> Array[int]:
	var result: Array[int] = []
	if include.is_empty():
		return result

	var driver: Dictionary = {}
	var driver_size := -1
	for type: Script in include:
		var table: Dictionary = _store.get(type, {})
		if table.is_empty():
			return result
		if driver_size < 0 or table.size() < driver_size:
			driver = table
			driver_size = table.size()

	for id: int in driver:
		var matched := true
		for type: Script in include:
			if not (_store[type] as Dictionary).has(id):
				matched = false
				break
		if matched:
			for type: Script in exclude:
				var table: Dictionary = _store.get(type, {})
				if table.has(id):
					matched = false
					break
		if matched:
			result.append(id)
	return result

## Every component on `id`. For the inspector and item records.
func components_of(id: int) -> Array[EcsComponent]:
	var found: Array[EcsComponent] = []
	for table: Dictionary in _store.values():
		var component: EcsComponent = table.get(id)
		if component != null:
			found.append(component)
	return found

# --- singletons -------------------------------------------------------------

## Stores world-level data that belongs to no entity.
func add_singleton(component: EcsComponent) -> EcsComponent:
	if component == null:
		push_error("EcsWorld: cannot add a null singleton")
		return null
	_singletons[component.get_script()] = component
	return component

func get_singleton(type: Script) -> EcsComponent:
	return _singletons.get(type)

func singletons() -> Array:
	return _singletons.values()
