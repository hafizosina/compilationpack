class_name EcsScheduler
extends RefCounted

## The ordered system list. Run order IS the coordination mechanism — wander
## writes a destination before movement walks toward it before render draws
## where it ended up — so this list is the pipeline, written once in main.gd
## and read like a table of contents.

var _systems: Array[EcsSystem] = []

## Appends a system and returns self, so a pipeline reads as one chained
## statement in the order it runs.
func add(system: EcsSystem) -> EcsScheduler:
	if system == null:
		push_error("EcsScheduler: refusing to add a null system")
		return self
	_systems.append(system)
	return self

## One frame: every system once, in order.
func run_all(world: EcsWorld, delta: float) -> void:
	for system in _systems:
		system.run(world, delta)

func systems() -> Array[EcsSystem]:
	return _systems
