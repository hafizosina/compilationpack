class_name EcsBodyComponent
extends EcsComponent

## The space an entity occupies: a circle that can be seen and reached.
## `is_solid` decides whether it also blocks; movability is EcsMovementComponent.

const NODE_KIND: StringName = EcsConst.NODE_BODY
## Bodies are the only detectable thing in the world.
const NODE_LAYER: int = EcsConst.LAYER_BODY
## Bodies detect bodies; that is what soft collision needs.
const NODE_MASK: int = EcsConst.LAYER_BODY

## Radius of the body in pixels, measured from the entity's position.
@export var radius: float = 24.0
## Whether it pushes and is pushed. Off for things walked over, like berries.
@export var is_solid: bool = true

func key() -> StringName:
	return &"body"

func describe() -> Dictionary:
	return {"tab": &"hidden", "lines": {}}
