class_name EcsPositionComponent
extends EcsComponent

## Where the entity is. The scene tree holds no authority over this — the
## Sprite2D that shows it is a view EcsNodeSyncSystem writes, one way, every
## frame.

@export var position: Vector2 = Vector2.ZERO

func key() -> StringName:
	return &"position"

## How the inspector shows it: its reading on the Entity tab. Display only;
## see EcsComponent.describe().
func describe() -> Dictionary:
	return {"tab": &"entity", "lines": {"position": "(%.0f, %.0f)" % [position.x, position.y]}}
