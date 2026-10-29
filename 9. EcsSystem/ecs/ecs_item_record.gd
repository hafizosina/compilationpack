class_name EcsItemRecord
extends RefCounted

## A carried item. Picking up kills the entity and stores its components here
## (all of them, no flags). `uid` survives pickup and drop; the entity id does not.

var uid: String = ""
var type_id: StringName = &""
var components: Array[EcsComponent] = []

## Snapshots entity `id` into a new record. Does not touch the entity.
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

## Copies every script variable, exported or not. `Resource.duplicate()` would
## drop the runtime fields.
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
