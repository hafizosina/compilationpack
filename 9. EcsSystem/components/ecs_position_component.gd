class_name EcsPositionComponent
extends EcsComponent

## Where the entity is, in global pixels.

@export var position: Vector2 = Vector2.ZERO

func key() -> StringName:
	return &"position"

func describe() -> Dictionary:
	return {"tab": &"entity", "lines": {"position": "(%.0f, %.0f)" % [position.x, position.y]}}
