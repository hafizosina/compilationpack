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
var _singletons: Dictionary = {}  # Script -> EcsComponent
## Script -> int, bumped whenever that table gains, loses or replaces an entry.
## A view compares these to the ones it was built from, and that comparison is
## the whole of its invalidation.
var _versions: Dictionary = {}
## [include, exclude] -> EcsView. Keyed on the arrays a system passes, which
## Godot hashes by content, so two systems asking the same question share one.
var _views: Dictionary = {}

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
	for type: Script in _store:
		if (_store[type] as Dictionary).erase(id):
			_versions[type] = int(_versions.get(type, 0)) + 1

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
	# Bumped on a replace as well as a new entry: a view holds the reference,
	# and the old one is no longer what is filed here.
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

## The answer to `query(include, exclude)`, with the components beside the ids
## — see EcsView. Built the first time it is asked for, then handed back as the
## same object until one of the tables it names changes, which in this module is
## a birth or death at the lifecycle stage, or a flag it names being raised or
## cleared. A view that names no flag is therefore rebuilt only on the ticks
## something is born or dies.
##
## A rebuild is one query() plus one dictionary read per component, so a view
## over a table that changes every tick costs more than query() does. Name a
## flag only if it changes rarely.
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

## Every component filed against `id`, in the order their types first appeared
## in the world. Exists for the inspector, which has to show an entity without
## knowing what it is; ordinary systems ask for the components they want by
## type and never enumerate.
func components_of(id: int) -> Array[EcsComponent]:
	var found: Array[EcsComponent] = []
	for table: Dictionary in _store.values():
		var component: EcsComponent = table.get(id)
		if component != null:
			found.append(component)
	return found

# --- singletons -------------------------------------------------------------

## World-level state that belongs to no entity — currently the click inbox the
## selection system drains. Stored beside the component tables rather than on a
## dummy entity so it never turns up in a query.
func add_singleton(component: EcsComponent) -> EcsComponent:
	if component == null:
		push_error("EcsWorld: cannot add a null singleton")
		return null
	_singletons[component.get_script()] = component
	return component

func get_singleton(type: Script) -> EcsComponent:
	return _singletons.get(type)
