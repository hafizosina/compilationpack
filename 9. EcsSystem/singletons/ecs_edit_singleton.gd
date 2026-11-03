class_name EcsEditSingleton
extends EcsSingleton

## Field edits from the inspector, waiting for EcsEditSystem.

## Pending edits, oldest first.
var edits: Array[EcsEdit] = []

func key() -> StringName:
	return &"edit"
