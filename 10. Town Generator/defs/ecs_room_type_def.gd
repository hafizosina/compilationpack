class_name EcsRoomTypeDef
extends Resource

## A room type, given to a room holding furniture with any of `needs`; the highest
## priority match wins.

@export var id: StringName = &""
@export var display_name: String = ""
## Furniture tags, any one of which makes a room this type.
@export var needs: Array[StringName] = []
@export var priority: int = 0
## Blueprints the generator puts in a room of this type: every required one, and each optional
## one by the building's wealth.
@export var required: Array[StringName] = []
@export var optional: Array[StringName] = []
## Its size inside its walls, smallest and largest, when a building grows room by room.
@export var size_min: Vector2i = Vector2i(3, 3)
@export var size_max: Vector2i = Vector2i(4, 4)
## Where it goes beside the main room when a building grows: &"front", &"back", &"side" or &"any".
@export var place: StringName = &"any"
## Where a piece goes, seen from the room's main door (BETTER_TOWNS_PLAN.md §4): blueprint ->
## &"back" (centred on the wall facing the door), &"side" (against a side wall), &"corner" (a back
## corner), &"beside_door" (just inside, off the way in), &"centre" (in the middle, off the way in) or
## &"rows" (anywhere off the way in). A piece not listed goes anywhere it fits, as before.
@export var layout: Dictionary[StringName, StringName] = {}
