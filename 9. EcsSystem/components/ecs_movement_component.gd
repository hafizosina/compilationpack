class_name EcsMovementComponent
extends EcsComponent

## Everything the movement system needs and nothing it does not. An entity
## without this component simply cannot move; that is the whole of "capability
## is component presence" for props.

## Travel speed in px/sec.
@export var speed: float = EcsConst.WALK_SPEED
## Distance at which the destination counts as reached.
@export var arrive_radius: float = 6.0

## Where it is heading. Written by whatever produces movement intent — the
## wander system now, a brain later.
var destination: Vector2 = Vector2.ZERO
## False means "standing still"; a Vector2 has no empty value to mean that.
var has_destination: bool = false
## Last frame's motion, for anything that wants facing or speed.
var velocity: Vector2 = Vector2.ZERO

func key() -> StringName:
	return &"movement"
