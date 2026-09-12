class_name EcsWorld
extends RefCounted

## Entity ids, component storage and the query engine. An entity is an int and
## nothing else — it owns no code, has no node, and exists only as the set of
## rows filed against its id here.
##
## Storage is `{ Script : { entity_id : EcsComponent } }`, one table per
## component type, and a query intersects the tables it was asked for. Naive,
## and correct into the thousands at this scale; an archetype store would sit
## behind this same API, which is why the API is the only thing systems see.
##
## Note the read accessor is `get_component()`, not `get()` — Object already
## defines `get(property)` and GDScript will not let it be redefined.

## Id 0 is reserved as "no entity", so an unset relationship field reads false
## through is_alive() without any null dance.
const NO_ENTITY: int = 0

var _next_id: int = 1
var _alive: Dictionary = {}  # entity_id -> true
var _store: Dictionary = {}  # Script -> { entity_id -> EcsComponent }

# --- entities ---------------------------------------------------------------

func create_entity() -> int:
	var id := _next_id
	_next_id += 1
	_alive[id] = true
	return id

## Removes the entity and every component filed against it. Ids are never
## reused, so a stale id held somewhere else goes permanently false through
## is_alive() instead of aliasing a new entity.
func destroy_entity(id: int) -> void:
	if not _alive.erase(id):
		return
	for table: Dictionary in _store.values():
		table.erase(id)

func is_alive(id: int) -> bool:
	return _alive.has(id)

func entity_count() -> int:
	return _alive.size()

# --- components -------------------------------------------------------------

## Files `component` against `id` under its own script type. Replaces whatever
## was there — one component of a kind per entity.
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
	return component

func get_component(id: int, type: Script) -> EcsComponent:
	var table: Dictionary = _store.get(type, {})
	return table.get(id)

func has(id: int, type: Script) -> bool:
	var table: Dictionary = _store.get(type, {})
	return table.has(id)

func remove(id: int, type: Script) -> void:
	var table: Dictionary = _store.get(type)
	if table != null:
		table.erase(id)

## Every entity carrying all of `include` and none of `exclude`, as a fresh
## array — safe to mutate the world while iterating the result.
##
## The scan is driven from the rarest of the requested types, so asking for
## [Position, Wander] costs the size of the wander table rather than the size
## of the world.
##
## Queries key on the script object, never a string: `query([EcsPositionComponent])`
## means a typo is a parse error instead of a silently empty result.
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
