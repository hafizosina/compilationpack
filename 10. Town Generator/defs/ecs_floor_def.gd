class_name EcsFloorDef
extends EcsTileDef

## A laid floor over the terrain: planks, stone, road, mat, path. `texture` and `tile_size` are a
## dual-grid sheet, read only when there is no `surface`.

## Its surface: a large seamless texture at EcsTownGrid.ART px a cell, shown where it lies
## (EcsTileSyncSystem, art/floor.gdshader). Without one, its sheet's full tile repeats.
@export var surface: Texture2D
## A worn path's edge: soft and ragged like the ground's, not a built floor's rigid square edge.
@export var soft: bool = false

## What a step onto it costs a walker, in place of the terrain's under it; 0 can't be walked.
@export var walk_cost: float = 1.0
