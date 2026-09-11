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
var _alive: Dictionary = {}       # entity_id -> true
var _store: Dictionary = {}       # Script -> { entity_id -> EcsComponent }
var _singletons: Dictionary = {}  # Script -> EcsComponent
var _events: Dictionary = {}      # Script -> Array[EcsEvent]

# --- entities ---------------------------------------------------------------

func create_entity() -> int:
	var id := _next_id
	_next_id += 1
	_alive[id] = true
	return id

## Removes the entity and every component filed against it. Ids are never
## reused, so a stale id held by some other component's relationship field goes
## permanently false through is_alive() instead of aliasing a new entity.
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
## [Position, AttackIntent] costs the size of the intent table rather than the
## size of the world.
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

## How many entities carry `type`. Cheap — it is one table's size.
func count(type: Script) -> int:
	var table: Dictionary = _store.get(type, {})
	return table.size()

# --- singletons -------------------------------------------------------------

## World-level state that belongs to no entity — the pending-command queue, and
## later the spatial index or the tuning block.
func add_singleton(component: EcsComponent) -> EcsComponent:
	if component == null:
		push_error("EcsWorld: cannot add a null singleton")
		return null
	_singletons[component.get_script()] = component
	return component

func get_singleton(type: Script) -> EcsComponent:
	return _singletons.get(type)

# --- events -----------------------------------------------------------------

## Records an event for this frame. Every system scheduled after the emitter
## sees it; nothing sees it next frame.
func emit_event(event: EcsEvent) -> void:
	if event == null:
		return
	var type: Script = event.get_script()
	if not _events.has(type):
		_events[type] = []
	(_events[type] as Array).append(event)

## This frame's events of one kind. The array is live — the crit system scaling
## an event's amount in place is exactly the intended use.
func events(type: Script) -> Array:
	return _events.get(type, [])

## Called by the scheduler at the end of every frame. Systems never call it.
func clear_events() -> void:
	_events.clear()
