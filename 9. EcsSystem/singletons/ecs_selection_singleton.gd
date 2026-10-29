class_name EcsSelectionSingleton
extends EcsSingleton

## A click waiting to be resolved by EcsSelectionSystem.

## True when a click is waiting.
var pending: bool = false
## Where the click landed, in world coordinates.
var pick_at: Vector2 = Vector2.ZERO

func key() -> StringName:
	return &"selection"
