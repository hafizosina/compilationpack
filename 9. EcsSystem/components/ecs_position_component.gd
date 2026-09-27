class_name EcsPositionComponent
extends EcsComponent

## Where the entity is. The scene tree holds no authority over this — the
## Sprite2D that shows it is a view EcsNodeSyncSystem writes, one way, every
## frame.

@export var position: Vector2 = Vector2.ZERO

## How the inspector shows it — see inspect/position_inspect.gd.
const INSPECTOR := preload("res://9. EcsSystem/inspect/position_inspect.gd")

func key() -> StringName:
	return &"position"
