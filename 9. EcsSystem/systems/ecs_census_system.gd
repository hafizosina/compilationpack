class_name EcsCensusSystem
extends EcsSystem

## Pushes the entity count to the stats panel on an interval. Pushed rather than
## polled so the panel never reaches into the world, and on an interval rather
## than at spawn because the count will start moving on its own once entities
## are born and eaten.

## How often the count is sent. Nothing reads it faster than a person can.
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
