class_name EcsRoomTypeDef
extends Resource

## A room type, given to a room holding furniture with any of `needs`; the highest
## priority match wins.

@export var id: StringName = &""
@export var display_name: String = ""
## Furniture tags, any one of which makes a room this type.
@export var needs: Array[StringName] = []
@export var priority: int = 0
