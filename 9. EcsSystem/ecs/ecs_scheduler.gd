class_name EcsScheduler
extends RefCounted

## The ordered system list. Run order IS the coordination mechanism — the attack
## system emits a damage event before the crit system scales it before the
## damage system applies it — so this list is the pipeline, written once and
## read like a table of contents.

var _systems: Array[EcsSystem] = []

## Appends a system and returns self, so a pipeline reads as one chained
## statement in the order it runs.
func add(system: EcsSystem) -> EcsScheduler:
	if system == null:
		push_error("EcsScheduler: refusing to add a null system")
		return self
	_systems.append(system)
	return self

## Runs every enabled system once, then drops the frame's events. Clearing here
## rather than in any one system is what makes events safe to fan out: every
## reader in this frame sees them, no reader in the next frame does.
func run_all(world: EcsWorld, delta: float) -> void:
	for system in _systems:
		if system.enabled:
			system.run(world, delta)
	world.clear_events()

## The system with the given label, or null. Lets a debug key flip one stage.
func find(system_label: StringName) -> EcsSystem:
	for system in _systems:
		if system.label() == system_label:
			return system
	return null

func systems() -> Array[EcsSystem]:
	return _systems
