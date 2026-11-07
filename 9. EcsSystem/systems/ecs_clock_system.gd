class_name EcsClockSystem
extends EcsSystem

## Advances the world clock by each tick's delta.

func label() -> StringName:
	return &"clock"

func run(world: EcsWorld, delta: float) -> void:
	var clock := world.get_singleton(EcsClockSingleton) as EcsClockSingleton
	if clock != null:
		clock.now += delta
