class_name EcsConsumableComponent
extends EcsComponent

## Marks something as food.

## Fullness gained when this is eaten.
@export var nutrition: float = 40.0
## What kind of food it is. Eaten only by creatures whose hunger `eats` this.
@export var diet: StringName = &"plant"

func key() -> StringName:
	return &"consumable"
