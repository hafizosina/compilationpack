class_name EcsWallDef
extends Resource

## A wall type: drawn on the cell grid from one atlas source of the walls' TileSet.

## Its name, unique among walls: what commands, saves and building defs refer to it by.
@export var key: StringName = &""
## The grid's number for it (`wall_type`), set by the catalog from its place in the list; 0 is none.
var id: int = 0
@export var display_name: String = ""
## Source id in the wall layer's TileSet.
@export var source_id: int = 1
## Hit points of one wall cell.
@export var max_hp: float = 100.0
## Blueprint left where a wall cell is destroyed, or empty for nothing.
@export var rubble: StringName = &""
