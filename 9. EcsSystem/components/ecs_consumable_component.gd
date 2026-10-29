class_name EcsConsumableComponent
extends EcsComponent

## Marks something as food.

## Fullness gained when this is eaten.
@export var nutrition: float = 40.0

func key() -> StringName:
	return &"consumable"
