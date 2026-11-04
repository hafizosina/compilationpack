class_name EcsEditSingleton
extends EcsSingleton

## Field edits and removals from the inspector, waiting for EcsEditSystem.

## Pending edits, oldest first.
var edits: Array[EcsEdit] = []
## Entities to remove.
var removals: Array[int] = []

func key() -> StringName:
	return &"edit"
