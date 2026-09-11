class_name EcsWanderComponent
extends EcsComponent

## Drift-around-aimlessly config. The wander system reads it and writes a
## destination into EcsMovementComponent; it never moves anything itself.

## How far from its current spot a new destination may be picked.
@export var radius: float = 260.0
## Shortest and longest idle pause between legs, in seconds.
@export var pause_min: float = 0.4
@export var pause_max: float = 2.5

## Seconds left of the current pause. Runtime state, not authored.
var pause_left: float = 0.0

func key() -> StringName:
	return &"wander"
