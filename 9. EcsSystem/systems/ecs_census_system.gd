class_name EcsCensusSystem
extends EcsSystem

## Sends the entity count to the UI every INTERVAL seconds, and every entity's
## id, name and type every LIST_INTERVAL seconds for the outliner.

## Seconds between count updates.
const INTERVAL: float = 0.5
## Seconds between entity lists.
const LIST_INTERVAL: float = 1.0

var _since: float = 0.0
var _since_list: float = LIST_INTERVAL

func label() -> StringName:
	return &"census"

func run(world: EcsWorld, delta: float) -> void:
	_since += delta
	_since_list += delta
	if _since >= INTERVAL:
		_since = 0.0
		EventBus.ecs_world_census.emit(world.entity_count())
	if _since_list >= LIST_INTERVAL:
		_since_list = 0.0
		EventBus.ecs_entities_listed.emit(entries(world))

## Every named entity as `{id, name, type}`.
static func entries(world: EcsWorld) -> Array:
	var listed: Array = []
	for id in world.query([EcsNameComponent]):
		var named := world.get_component(id, EcsNameComponent) as EcsNameComponent
		listed.append({"id": id, "name": String(named.entity_name), "type": String(named.type_id)})
	return listed
