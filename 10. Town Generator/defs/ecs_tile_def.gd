class_name EcsTileDef
extends Resource

## A tile type drawn on the dual grid, from its own TileSet. Its place in its catalog list
## is its draw order: a later type draws over an earlier one.

## Its name, unique within its list: what commands, saves and building defs refer to it by.
@export var key: StringName = &""
## The grid's number for it, set by the catalog from its place in its list; 0 is none.
var id: int = 0
@export var display_name: String = ""
## Its tiles: one atlas source, laid out by terrain peering bits or, without them, by
## transparency. A tile size other than the grid's cell is scaled to fit.
@export var tile_set: TileSet
