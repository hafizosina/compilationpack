class_name EcsDoorDef
extends Resource

## A door type: its blueprint, and a sheet per state with the tile for each direction. A
## horizontal door sits in a wall running left-right. Door tiles may be bigger than a cell;
## they are drawn centred on it.

## Its name, unique among doors: what commands, saves and building defs refer to it by.
@export var key: StringName = &""
## The grid's number for it (`wall_type` on a DOOR cell), set by the catalog from its place in the list.
var id: int = 0
@export var display_name: String = ""
## Entity blueprint spawned for each door.
@export var blueprint: StringName = &"door"
## Tile size in both sheets, in pixels.
@export var tile_size: int = 48
@export var closed_texture: Texture2D
## Pixels before the first tile, from the left and the top.
@export var closed_margins: Vector2i = Vector2i.ZERO
@export var closed_horizontal: Vector2i = Vector2i(0, 0)
@export var closed_vertical: Vector2i = Vector2i(1, 0)
@export var open_texture: Texture2D
@export var open_margins: Vector2i = Vector2i.ZERO
@export var open_horizontal: Vector2i = Vector2i(2, 0)
@export var open_vertical: Vector2i = Vector2i(3, 0)
## Their sources in the walls' TileSet, set by the catalog when it makes that TileSet.
var closed_source_id: int = -1
var open_source_id: int = -1
