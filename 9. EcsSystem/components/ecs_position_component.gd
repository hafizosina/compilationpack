class_name EcsPositionComponent
extends EcsComponent

## Where the entity is. The scene tree holds no authority over this — the
## Sprite2D that shows it is a view the render system writes, one way, every
## frame.

@export var position: Vector2 = Vector2.ZERO

func key() -> StringName:
	return &"position"
