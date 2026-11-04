class_name EcsFurnitureComponent
extends EcsComponent

## Furniture: what it counts as when a room is typed, and whether it holds attachments.

## What it is to a room: &"bed", &"stove", &"table", &"workbench", &"storage", &"seat", ...
@export var tags: Array[StringName] = []
## Takes attachments on top, one per cell it covers.
@export var holds: bool = false

func key() -> StringName:
	return &"furniture"
