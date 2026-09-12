class_name EcsLowBrainComponent
extends EcsComponent

## The simplest brain there is: drift somewhere nearby, pause, drift again.
##
## Named for its rank rather than its behaviour, because what it *is* is the
## bottom of the decision ladder — the plan's later steps add an FSM and then a
## planner above it. All any of them do is write a destination into
## EcsMovementComponent, so a higher brain replaces this one without the
## movement system, the render system or anything else noticing.
##
## Carrying this component is the whole of "this entity decides for itself".

## How far from its current spot a new destination may be picked.
@export var radius: float = 260.0
## Shortest and longest idle pause between legs, in seconds.
@export var pause_min: float = 0.4
@export var pause_max: float = 2.5

## Seconds left of the current pause. Runtime state, not authored.
var pause_left: float = 0.0

func key() -> StringName:
	return &"low_brain"
