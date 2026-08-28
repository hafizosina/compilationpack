class_name SimComponentDef
extends Resource

## Abstract blueprint for one component: it holds that component's authored
## config and knows how to build the runtime node from it.
##
## Adding a new component kind means adding a new SimComponentDef subclass —
## SimEntityFactory never switches on type and never needs touching.
##
## CONTRACT for subclasses:
## - `slot()` must return a unique, stable key. It identifies the component for
##   `SimEntity.get_component()` AND is the key a SimPlacement override targets.
## - `build_into()` receives a def that the factory has already deep-duplicated
##   for this one entity, so mutating `self` here is safe and local.
## - Any Resource held as LIVE MUTABLE STATE must be `duplicate()`d in
##   `build_into()`, not referenced. Immutable config (a Texture2D, later an
##   ActionDef) may be shared freely.

## Slot key this def builds into. Override in every subclass.
func slot() -> StringName:
	return &""

## Instantiate + configure this component on `entity`, add it as a child, and
## register it via `entity.register_component()`. The entity is already inside
## the scene tree when this runs, so its @onready members are valid.
func build_into(_entity: SimEntity) -> void:
	push_error("SimComponentDef.build_into() not implemented by %s" % get_class())
