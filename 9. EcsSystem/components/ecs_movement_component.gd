class_name EcsMovementComponent
extends EcsComponent

## Everything the movement system needs and nothing it does not. An entity
## without this component simply cannot move; that is the whole of "capability
## is component presence" for props.

## Travel speed in px/sec.
@export var speed: float = EcsConst.WALK_SPEED
## Distance at which the destination counts as reached.
@export var arrive_radius: float = 6.0
## How many times longer than the trip should take before the destination is
## given up on. 1.0 would expire on a flawless straight walk; the slack is what
## pays for soft collision shoving it off the line on the way.
@export var timeout_slack: float = 2.5
## Seconds added on top of the priced trip, so a destination a few pixels away
## still gets a fair try rather than a budget of nearly nothing.
@export var timeout_grace: float = 0.5

## Where it is heading. Written by whatever produces movement intent — the
## wander system now, a brain later.
var destination: Vector2 = Vector2.ZERO
## False means "standing still"; a Vector2 has no empty value to mean that.
var has_destination: bool = false
## Last frame's motion, for anything that wants facing or speed.
var velocity: Vector2 = Vector2.ZERO
## Seconds left to reach `destination`. Zero alongside a live destination means
## the trip has not been priced yet — the movement system does that on the tick
## it first sees it, and puts it back to zero when the trip ends either way.
var time_left: float = 0.0

func key() -> StringName:
	return &"movement"
