class_name EcsGridPositionComponent
extends EcsComponent

## Where a static thing stands on the town grid: its top-left cell and how many cells
## it covers. The authority for the grid; EcsPositionComponent is its centre, set at birth.

var cell: Vector2i = Vector2i.ZERO
@export var size: Vector2i = Vector2i.ONE

func key() -> StringName:
	return &"grid_position"
