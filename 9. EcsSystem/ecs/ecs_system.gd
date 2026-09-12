class_name EcsSystem
extends RefCounted

## Base for every system. Systems hold ALL behaviour: a system reads components
## through `world.query()`, writes components, and never calls another system.
## Coordination happens through shared components and the scheduler's run order
## — nothing else.

## Short name for debug listings.
func label() -> StringName:
	return &"system"

## One frame of work over `world`. Override in every subclass.
func run(_world: EcsWorld, _delta: float) -> void:
	push_error("EcsSystem.run() not implemented by %s" % label())
