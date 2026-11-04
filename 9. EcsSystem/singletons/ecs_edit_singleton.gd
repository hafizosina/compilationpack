class_name EcsEditSingleton
extends EcsSingleton

## Field edits and removals from the inspector, waiting for EcsEditSystem.

## Pending edits, oldest first.
var edits: Array[EcsEdit] = []
## Entities to remove.
var removals: Array[int] = []
## Counts runs that applied an edit, so node sync knows to redraw.
var applied: int = 0

func key() -> StringName:
	return &"edit"
