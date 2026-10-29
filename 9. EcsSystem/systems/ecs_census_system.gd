class_name EcsCensusSystem
extends EcsSystem

## Sends the entity count to the UI every INTERVAL seconds.

## Seconds between updates.
const INTERVAL: float = 0.5

var _since: float = 0.0

func label() -> StringName:
	return &"census"

func run(world: EcsWorld, delta: float) -> void:
	_since += delta
	if _since < INTERVAL:
		return
	_since = 0.0
	EventBus.ecs_world_census.emit(world.entity_count())
