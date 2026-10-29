class_name EcsLifecycleSystem
extends EcsSystem

## Runs EcsEntityManager's drain. First in the pipeline: all births and deaths
## happen here.

var _manager: EcsEntityManager
var _catalog: EcsEntityCatalog

func _init(manager: EcsEntityManager, catalog: EcsEntityCatalog) -> void:
	_manager = manager
	_catalog = catalog

func label() -> StringName:
	return &"lifecycle"

func run(world: EcsWorld, _delta: float) -> void:
	if _manager == null or _catalog == null:
		return
	_manager.drain(world, _catalog)
