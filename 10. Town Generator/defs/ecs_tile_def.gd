class_name EcsTileDef
extends Resource

## A tile type drawn on the dual grid. Its art, tile size and offset are the scene's:
## `layer` names its TileMapLayer under the town's tile group, and that layer's place
## among its siblings is its draw order.

## Stable catalog id, stored in the grid; never derived from load order. 0 is reserved for none.
@export var id: int = 0
@export var display_name: String = ""
## Name of the TileMapLayer that draws it.
@export var layer: StringName = &""
