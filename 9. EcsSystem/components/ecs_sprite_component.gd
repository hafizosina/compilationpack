class_name EcsSpriteComponent
extends EcsComponent

## How the entity looks. EcsNodeSyncSystem copies it onto the Sprite2D.

const NODE_KIND: StringName = EcsConst.NODE_SPRITE

@export var texture: Texture2D
## Uniform scale for the texture.
@export var scale_factor: float = EcsConst.SPRITE_SCALE
## Colour multiplier.
@export var tint: Color = Color.WHITE
## Draw order.
@export var z_index: int = 0

func key() -> StringName:
	return &"sprite"

func describe() -> Dictionary:
	return {"tab": &"hidden", "lines": {}}
