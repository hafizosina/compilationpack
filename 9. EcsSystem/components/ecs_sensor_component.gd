class_name EcsSensorComponent
extends EcsComponent

## Sight: the bodies within `radius`, found by a physics area.

const NODE_KIND: StringName = EcsConst.NODE_SENSOR
## No layer, so sensors never detect each other.
const NODE_LAYER: int = EcsConst.LAYER_NONE
const NODE_MASK: int = EcsConst.LAYER_BODY

## Sight radius in pixels, from the entity's position.
@export var radius: float = 260.0

## Ids of bodies in sight as of the last tick, written by EcsSensorSystem.
## Never contains the entity itself.
var perceived: Array[int] = []

func key() -> StringName:
	return &"sensor"

func describe() -> Dictionary:
	return {"tab": &"hidden", "lines": {}}
