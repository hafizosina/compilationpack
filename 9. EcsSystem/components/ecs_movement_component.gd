class_name EcsMovementComponent
extends EcsComponent

## Lets an entity move toward a destination.

## Travel speed in px/sec.
@export var speed: float = EcsConst.WALK_SPEED
## Distance at which the destination counts as reached.
@export var arrive_radius: float = 6.0
## A trip times out after its expected duration times this.
@export var timeout_slack: float = 2.5
## Seconds added to every trip's time budget.
@export var timeout_grace: float = 0.5

## Where it is heading.
var destination: Vector2 = Vector2.ZERO
## False means standing still.
var has_destination: bool = false
## Motion this tick.
var velocity: Vector2 = Vector2.ZERO
## Seconds left on the trip. Zero with a live destination means not yet priced.
var time_left: float = 0.0

func key() -> StringName:
	return &"movement"
