class_name EcsWallDef
extends EcsTileDef

## A wall: a tile type like a terrain, but on the cell grid, its sheet holding the 16 side
## shapes (ends, runs, corners, T-junctions, a cross, a lone post) in any arrangement, told
## apart by their pixels.

## Its source in the walls' TileSet, set by the catalog when it makes that TileSet.
var source_id: int = -1
## Hit points of one wall cell.
@export var max_hp: float = 100.0
## Blueprint left where a wall cell is destroyed, or empty for nothing.
@export var rubble: StringName = &""
