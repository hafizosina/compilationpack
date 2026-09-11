class_name EcsNameComponent
extends EcsComponent

## Identity as data: what this entity is called, and what blueprint it came out
## of. Added by the factory from the placement and the blueprint, never by a
## blueprint's own component list — every entity has an identity, and it is not
## a property of its type.
##
## The name is also the only thing an authored relationship can point at: a
## .tres cannot write an integer id it has no way of knowing, so it names its
## weapon and EcsEquipSystem turns that name into an id once, at runtime.

## Unique name for this instance, from EcsPlacement.entity_name.
@export var entity_name: StringName = &""
## Blueprint id this instance was built from.
@export var type_id: StringName = &""
## The blueprint's human-readable name, for the inspector title.
@export var display_name: String = ""

func key() -> StringName:
	return &"name"
