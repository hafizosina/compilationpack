class_name EcsWanderComponent
extends EcsComponent

## Walks to a random point nearby, pauses, and goes again. Walls don't stop it yet.

## How far one walk may go, in px.
@export var radius: float = 160.0
## Seconds to stand between walks, picked in this range.
@export var pause_min: float = 0.5
@export var pause_max: float = 3.0

## Seconds left standing.
var pause_left: float = 0.0

func key() -> StringName:
	return &"wander"
