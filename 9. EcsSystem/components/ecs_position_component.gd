class_name EcsPositionComponent
extends EcsComponent

## Where the entity is. The scene tree holds no authority over this — the
## Sprite2D that shows it is a view EcsNodeSyncSystem writes, one way, every
## frame.

## One line every entity has: it goes on the inspector's Entity tab rather
## than a tab of its own.
const INSPECT_ON_ENTITY_TAB := [&"position"]

@export var position: Vector2 = Vector2.ZERO

func key() -> StringName:
	return &"position"
