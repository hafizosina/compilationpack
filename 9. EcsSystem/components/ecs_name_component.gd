class_name EcsNameComponent
extends EcsComponent

## Identity: name, blueprint and uid. Added by EcsEntityManager at spawn.

## Unique name for this instance, from EcsPlacement.entity_name.
@export var entity_name: StringName = &""
## Blueprint id this instance was built from.
@export var type_id: StringName = &""
## The blueprint's human-readable name, for the inspector title.
@export var display_name: String = ""
## Stable identity that survives pickup and drop, unlike the entity id.
var uid: String = ""

func key() -> StringName:
	return &"name"

func describe() -> Dictionary:
	return {
		"tab": &"entity",
		"title": {"name": String(entity_name), "type": String(type_id)},
		"lines": {"entity_name": String(entity_name), "blueprint": display_name},
	}
