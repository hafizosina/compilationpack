class_name EcsActionComponent
extends EcsComponent

## Reach: the bodies close enough to act on. Keep `radius` larger than the
## entity's own body radius, or soft collision stops it before it can reach.

const NODE_KIND: StringName = EcsConst.NODE_ACTION
const NODE_LAYER: int = EcsConst.LAYER_NONE
const NODE_MASK: int = EcsConst.LAYER_BODY

## Reach radius in pixels, from the entity's position.
@export var radius: float = 34.0

## Ids of bodies in reach as of the last tick, written by EcsSensorSystem.
## Never contains the entity itself.
var reached: Array[int] = []

func key() -> StringName:
	return &"action"

func describe() -> Dictionary:
	return {"tab": &"hidden", "lines": {}}
