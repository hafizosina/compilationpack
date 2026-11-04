class_name EcsDoorComponent
extends EcsComponent

## A door in a wall line. Its cell is DOOR in the grid; open and closed are a tile swap.

@export var is_open: bool = false
@export var is_locked: bool = false

func key() -> StringName:
	return &"door"
