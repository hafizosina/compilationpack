class_name EcsSettlementDef
extends Resource

## A kind of settlement map: its size, its water, how much is rock and forest, and what grows where.
## As the child of a refine (EcsTerrainGenerator.refine), only its size, shore width and nodes are read.

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
@export var nodes: Array[EcsNodeSpawnDef] = []
