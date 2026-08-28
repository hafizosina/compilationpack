class_name SimSpriteDef
extends SimComponentDef

## Appearance blueprint. Unlike the other defs this adds no node — it configures
## the Sprite2D the bare entity scene already owns. It still lives in the
## blueprint's `components` array so that *everything* about an entity is
## authored in one list, and the factory keeps zero special cases.

## Texture drawn for this entity type.
@export var texture: Texture2D
## Uniform scale applied to the texture. The ~128px animal art needs 0.5 to
## cover one 64px tile.
@export var scale_factor: float = SimConst.SPRITE_SCALE
## Colour multiplier — the per-type tint that makes the eyeball test work.
@export var tint: Color = Color.WHITE

func slot() -> StringName:
	return &"sprite"

func build_into(entity: SimEntity) -> void:
	entity.sprite.texture = texture
	entity.sprite.scale = Vector2.ONE * scale_factor
	entity.sprite.modulate = tint
	# The Sprite2D already exists on the bare scene, so this def adds no node —
	# it registers the existing one so `sprite` shows up like any other slot.
	entity.register_component(slot(), entity.sprite)
