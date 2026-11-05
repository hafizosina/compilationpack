class_name EcsRespawnComponent
extends EcsComponent

## After `after` seconds, a `blueprint` is born where this stands, and this goes.

## What comes back.
@export var blueprint: StringName = &""
## Seconds until it does.
@export var after: float = 3.0

## Seconds counted so far.
var waited: float = 0.0

func key() -> StringName:
	return &"respawn"
