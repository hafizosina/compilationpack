class_name EcsLifecycleSystem
extends EcsSystem

## Puts EcsEntityManager's drain in the pipeline, first, where the run order is
## readable: every birth and death in module 9 happens at this stage and at no
## other point in the frame.
##
## It is this thin on purpose. The manager is a service rather than a system so
## that the systems looking nodes up on it are not reaching into another
## system; this is the seam that still lets the scheduler list structural
## change as a stage you can read in main.gd's chain.

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
