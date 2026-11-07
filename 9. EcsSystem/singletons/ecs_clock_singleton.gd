class_name EcsClockSingleton
extends EcsSingleton

## Simulated seconds since the world began. Only EcsClockSystem advances it; it stops while
## paused and a save keeps it, so anything stamped with it ages in game time.

var now: float = 0.0

func key() -> StringName:
	return &"clock"

## `world`'s time; 0 if the world has no clock.
static func now_of(world: EcsWorld) -> float:
	var clock := world.get_singleton(EcsClockSingleton) as EcsClockSingleton
	return clock.now if clock != null else 0.0
