class_name EcsGridPositionComponent
extends EcsComponent

## Where a static thing stands on the town grid: its top-left cell and how many cells
## it covers. The authority for the grid; EcsPositionComponent is its centre, set at birth.

var cell: Vector2i = Vector2i.ZERO
## Cells it covers: in a blueprint as drawn, on a placed piece as turned.
@export var size: Vector2i = Vector2i.ONE
## Quarter turns clockwise it was placed with.
var turns: int = 0

func key() -> StringName:
	return &"grid_position"
