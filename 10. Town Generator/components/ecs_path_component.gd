class_name EcsPathComponent
extends EcsComponent

## Walks to a goal cell along a path over the town grid, feeding one cell at a time to
## EcsMovementComponent's destination. Set `goal` and `wants` to ask; EcsPathSystem plans it.

## The cell it is asked to reach.
var goal: Vector2i = Vector2i.ZERO
## True while a path to `goal` is wanted and not yet planned.
var wants: bool = false
## The cells still to walk, in order.
var cells: Array[Vector2i] = []
## Index into `cells` of the next cell to hand to movement.
var next: int = 0
## The nav revision the path was last checked against.
var revision: int = 0
## True when the last ask found no way to its goal.
var failed: bool = false

func key() -> StringName:
	return &"path"
