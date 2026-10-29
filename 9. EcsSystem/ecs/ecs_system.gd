class_name EcsSystem
extends RefCounted

## Base for every system. Systems hold all behaviour and never call each other.

## Short name for debug listings.
func label() -> StringName:
	return &"system"

## One frame of work over `world`. Override in every subclass.
func run(_world: EcsWorld, _delta: float) -> void:
	push_error("EcsSystem.run() not implemented by %s" % label())
