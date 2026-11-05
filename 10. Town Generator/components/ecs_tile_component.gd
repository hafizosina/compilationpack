class_name EcsTileComponent
extends EcsComponent

## Drawn as tiles, cut from `texture`: `atlas` is the tile of its top-left cell; a piece
## covering several cells draws the matching neighbouring tiles. A tile smaller than a cell
## is drawn centred on it.

@export var texture: Texture2D
## Tile size in the sheet, in pixels.
@export var tile_size: int = 32
@export var atlas: Vector2i = Vector2i.ZERO

func key() -> StringName:
	return &"tile"
