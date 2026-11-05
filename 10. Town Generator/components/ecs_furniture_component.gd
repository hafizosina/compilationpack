class_name EcsFurnitureComponent
extends EcsComponent

## Furniture: what it counts as when a room is typed, and whether it holds attachments.

## What it is to a room: &"bed", &"stove", &"table", &"workbench", &"storage", &"seat", ...
@export var tags: Array[StringName] = []
## Takes attachments on top, one per cell it covers.
@export var holds: bool = false
## Stands with its back to a wall (a bed's head, a stove's back): the generator places it so.
## Its back is its top edge as drawn, unturned.
@export var against_wall: bool = false

func key() -> StringName:
	return &"furniture"
