class_name EcsSystem
extends RefCounted

## Base for every system. Systems hold ALL behaviour: a system reads components
## through `world.query()`, writes components and events, and never calls
## another system. Coordination happens through shared components, events and
## the scheduler's run order — nothing else.

## Scheduler skips a disabled system. Used to demonstrate that a whole stage
## (crits, say) can be pulled out of the pipeline without any other system
## noticing.
var enabled: bool = true

## Short name for debug listings.
func label() -> StringName:
	return &"system"

## One frame of work over `world`. Override in every subclass.
func run(_world: EcsWorld, _delta: float) -> void:
	push_error("EcsSystem.run() not implemented by %s" % label())
