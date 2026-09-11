class_name EcsSpriteComponent
extends EcsComponent

## What the entity looks like — still data. The render system reads it and
## pushes the values onto a pooled Sprite2D; anything wanting to change an
## entity's appearance writes here, which is why the death system darkens
## `tint` rather than reaching for a node.

@export var texture: Texture2D
## Uniform scale for the texture. The ~128px animal art needs 0.5 per tile.
@export var scale_factor: float = EcsConst.SPRITE_SCALE
## Colour multiplier — the per-type tint that makes the eyeball test work.
@export var tint: Color = Color.WHITE
## Draw order, so a wielded dagger sits over its wielder.
@export var z_index: int = 0

func key() -> StringName:
	return &"sprite"
