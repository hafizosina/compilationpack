class_name WorldLandDef
extends Resource

## What the land is, for WorldTerrainGenerator: its size, its water, how much is rock and forest, its
## deposits and what grows where. A region (L2) names the land its L1 refines into as `child`;
## of a child only the shore width and nodes are read.

## RIVER_TO_SEA: a coast on one side and a river from the far edge into it.
enum Water { LAKE, RIVER, COAST, RIVER_TO_SEA }

@export var key: StringName = &""
@export var display_name: String = ""
## Map size in cells.
@export var size: Vector2i = Vector2i(160, 120)
@export var water: Water = Water.LAKE
## Share of the map under water, rock and forest; each is hit within the terrain check's tolerance.
@export var water_share: float = 0.12
@export var rock_share: float = 0.08
@export var forest_share: float = 0.25
## Land within this many cells of water is sand.
@export var shore_width: int = 2
## A river's width in cells, picked in this range along its length.
@export var river_width: Vector2i = Vector2i(3, 6)
## What grows where, placed in this order.
@export var nodes: Array[WorldNodeSpawnDef] = []
## Deposits of ore and clay, placed as blobs on their ground; a region's are what its L1 veins grow in.
@export var deposits: Array[WorldDepositDef] = []
## The land its L1 refines into: the shore width and nodes of the chunks and of a town's area.
@export var child: WorldLandDef
