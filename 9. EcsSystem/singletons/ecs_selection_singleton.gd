class_name EcsSelectionSingleton
extends EcsSingleton

## A click, drag box or picked id waiting to be resolved by EcsSelectionSystem.

## True when a pick is waiting.
var pending: bool = false
## Where the click landed, or where the box began, in world coordinates.
var pick_at: Vector2 = Vector2.ZERO
## The box's other corner, when `is_box`.
var drag_to: Vector2 = Vector2.ZERO
## An entity picked by id (from the outliner), or NO_ENTITY to use the click or box.
var pick_id: int = EcsWorld.NO_ENTITY
## True for a drag box, false for a click.
var is_box: bool = false
## Shift held: a click or id toggles one entity and a box adds, instead of replacing.
var additive: bool = false

func key() -> StringName:
	return &"selection"
