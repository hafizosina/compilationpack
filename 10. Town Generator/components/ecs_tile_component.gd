class_name EcsTileComponent
extends EcsComponent

## Drawn as tiles: `atlas` is the tile of its top-left cell on its layer (the catalog's
## furniture or attachment layer); a piece covering several cells draws the matching
## neighbouring tiles.

@export var source_id: int = 0
@export var atlas: Vector2i = Vector2i.ZERO

func key() -> StringName:
	return &"tile"
