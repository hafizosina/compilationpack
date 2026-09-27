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
## Who this thing is, for as long as it is anything. The entity id is the
## store's key and changes when an item is picked up and put back; this does
## not. Set by EcsEntityManager at first spawn and carried by EcsItemRecord.
## Runtime, not authored: a .tres cannot know it.
var uid: String = ""

func key() -> StringName:
	return &"name"

## How the inspector shows it: it titles the panel, and puts the entity name and
## blueprint on the Entity tab. Display only; see EcsComponent.describe().
func describe() -> Dictionary:
	return {
		"tab": &"entity",
		"title": {"name": String(entity_name), "type": String(type_id)},
		"lines": {"entity_name": String(entity_name), "blueprint": display_name},
	}
