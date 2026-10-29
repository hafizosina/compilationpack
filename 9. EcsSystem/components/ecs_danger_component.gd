class_name EcsDangerComponent
extends EcsComponent

## How threatened it feels, 0 to 1. EcsDangerSystem fills it while something that
## could hunt it is in sight, jumps it on a hit, and lets it decay otherwise.

## Rise per second while a threat is in sight.
@export var fill: float = 1.5
## Rise when hit.
@export var hit_jump: float = 0.5
## Fall per second with no threat in sight.
@export var decay: float = 0.2
## At or above this it wants to flee.
@export var flee_at: float = 0.3

## Current danger.
var value: float = 0.0
## The last thing that threatened it, and where it was.
var threat: int = EcsWorld.NO_ENTITY
var threat_at: Vector2 = Vector2.ZERO

func key() -> StringName:
	return &"danger"

func describe() -> Dictionary:
	return {"tab": &"entity", "lines": {"danger": "%d%%" % roundi(value * 100.0)}}
