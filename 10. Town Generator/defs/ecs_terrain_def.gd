class_name EcsTerrainDef
extends EcsTileDef

## Ground under everything: grass, dirt, sand, water. `texture` and `tile_size` are a
## dual-grid sheet, read only when there is no `ground`.

## Its ground: a large seamless texture at EcsTownGrid.ART px a cell, shown where it lies with
## soft edges (EcsTileSyncSystem). Without one, its sheet's full tile repeats.
@export var ground: Texture2D
## What a step onto it costs a walker; 0 can't be walked. A floor laid over it sets its own.
@export var walk_cost: float = 1.0
