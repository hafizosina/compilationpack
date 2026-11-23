class_name EcsTileComponent
extends EcsComponent

## Drawn as tiles, cut from `texture`: `atlas` is the tile of its top-left cell; a piece
## covering several cells draws the matching neighbouring tiles. A tile smaller than a cell
## is drawn centred on it.

@export var texture: Texture2D
## Tile size in the sheet, in pixels, at EcsTownGrid.ART pixels a cell.
@export var tile_size: int = 64
@export var atlas: Vector2i = Vector2i.ZERO
## A link group: when set, drawn by which side neighbours share it, from a 16-shape sheet in the walls' side layout, or a 6-tile sheet for a gate (across or down, posts where its fence meets it); `atlas` is then only its icon.
@export var link: StringName = &""

func key() -> StringName:
	return &"tile"
