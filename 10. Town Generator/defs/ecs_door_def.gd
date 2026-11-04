class_name EcsDoorDef
extends Resource

## A door type: its blueprint and the wall layer's tiles for each state and direction.
## A horizontal door sits in a wall running left-right.

## Stable catalog id, stored in the grid's `wall_type` on a DOOR cell; 0 is reserved for none.
@export var id: int = 0
@export var display_name: String = ""
## Entity blueprint spawned for each door.
@export var blueprint: StringName = &"door"
@export var closed_source_id: int = 2
@export var closed_horizontal: Vector2i = Vector2i(0, 0)
@export var closed_vertical: Vector2i = Vector2i(1, 0)
@export var open_source_id: int = 4
@export var open_horizontal: Vector2i = Vector2i(2, 0)
@export var open_vertical: Vector2i = Vector2i(3, 0)
