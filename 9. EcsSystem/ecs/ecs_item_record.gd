class_name EcsItemRecord
extends RefCounted

## A carried item: an entity that stopped existing and became data.
##
## Picking something up **kills** it and puts one of these in the bag. In most
## games an item in a bag, a chest or a shop is not a live entity, and this is
## that. It reverses step 3's "items stay entities": what a carried item should
## *do* while carried — durability, rot — is deferred, and a record does nothing.
##
## It keeps **every component, Position included**, and no flags. Everything,
## because nobody knows yet what a future item will need, and the catalog only
## holds a type's defaults, not the per-placement values an instance was given.
## Position goes stale in the bag and nothing reads it there; putting the item
## back overwrites it. Flags are what was true of the entity *then* — a dropped
## berry should not come back selected.
##
## The copy walks `PROPERTY_USAGE_SCRIPT_VARIABLE`, not `Resource.duplicate()`.
## Measured: duplicate() copies only `@export` fields, so an energy component at
## 12.5 came back at its default 100 and a bag holding two ids came back empty.
## Arrays and dictionaries are deep-copied; a field holding an object is shared.
##
## `uid` is who the thing is. The entity id is the store's key and a dropped item
## gets a new one; the uid survives pickup and drop.

var uid: String = ""
var type_id: StringName = &""
var components: Array[EcsComponent] = []

## Snapshots entity `id` into a new record. Does not touch the entity — killing
## it is the caller's business.
static func capture(world: EcsWorld, id: int) -> EcsItemRecord:
	var record := EcsItemRecord.new()
	for component in world.components_of(id):
		if component is EcsFlag:
			continue
		record.components.append(copy(component))
	var named := world.get_component(id, EcsNameComponent) as EcsNameComponent
	if named != null:
		record.uid = named.uid
		record.type_id = named.type_id
	return record

## The snapshot's component of `type`, or null.
func component(type: Script) -> EcsComponent:
	for held in components:
		if held.get_script() == type:
			return held
	return null

## A field-for-field copy of a component, exported and runtime fields alike.
static func copy(source: EcsComponent) -> EcsComponent:
	var twin: EcsComponent = source.get_script().new()
	for entry in source.get_property_list():
		if not (int(entry["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var value: Variant = source.get(entry["name"])
		if value is Array or value is Dictionary:
			value = value.duplicate(true)
		twin.set(entry["name"], value)
	return twin
