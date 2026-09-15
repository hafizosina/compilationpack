class_name EcsSelectionComponent
extends EcsComponent

## World singleton: the click inbox. `_unhandled_input` records where the mouse
## went down and EcsSelectionSystem resolves it at the top of the next frame,
## so picking obeys the same rule as everything else — only a system reads the
## world and only a system writes components.

## True when a click is waiting to be resolved.
var pending: bool = false
## Where that click landed, in world coordinates.
var pick_at: Vector2 = Vector2.ZERO

func key() -> StringName:
	return &"selection"
