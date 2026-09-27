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

## Only the name goes on the inspector's Entity tab, and the component gets no
## tab of its own; type, display name and uid are the header's or nobody's.
const INSPECT_ON_ENTITY_TAB := [&"entity_name"]

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
