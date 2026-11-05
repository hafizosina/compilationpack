class_name EcsTileDef
extends Resource

## A tile type: a sheet and its tile size, nothing else. The TileSet and which tile is which
## shape are worked out from the sheet's pixels at start. Terrain, floor and roof are on the
## dual grid, by corner (EcsDualGrid.corner_layout); a wall on the cell grid, by side. Its
## place in its catalog list is its draw order: a later type draws over an earlier one.

## Its name, unique within its list: what commands, saves and building defs refer to it by.
@export var key: StringName = &""
## The grid's number for it, set by the catalog from its place in its list; 0 is none.
var id: int = 0
@export var display_name: String = ""
## The sheet: its shapes in any arrangement, extra full tiles as variants.
@export var texture: Texture2D
## Tile size in the sheet, in pixels; one other than the grid's cell is scaled to fit.
@export var tile_size: int = 32
