class_name EcsWallDef
extends Resource

## A wall type: drawn on the cell grid from one atlas source of the walls' TileSet.

## Stable catalog id, stored in the grid's `wall_type`; 0 is reserved for none.
@export var id: int = 0
@export var display_name: String = ""
## Source id in the wall layer's TileSet.
@export var source_id: int = 1
## Hit points of one wall cell.
@export var max_hp: float = 100.0
## Blueprint left where a wall cell is destroyed, or empty for nothing.
@export var rubble: StringName = &""
