class_name EcsTileDef
extends Resource

## A tile type drawn on the dual grid. Its art, tile size and offset are the scene's:
## `layer` names its TileMapLayer under the town's tile group, and that layer's place
## among its siblings is its draw order.

## Its name, unique within its list: what commands, saves and building defs refer to it by.
@export var key: StringName = &""
## The grid's number for it, set by the catalog from its place in its list; 0 is none.
var id: int = 0
@export var display_name: String = ""
## Name of the TileMapLayer that draws it.
@export var layer: StringName = &""
