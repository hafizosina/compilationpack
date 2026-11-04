class_name EcsTownCatalog
extends Resource

## Every tile type the town can draw, looked up by stable id.

@export var terrains: Array[EcsTerrainDef] = []
@export var floors: Array[EcsFloorDef] = []
@export var walls: Array[EcsWallDef] = []
## Name of the TileMapLayer that draws walls and doors, on the cell grid.
@export var wall_layer: StringName = &"ObjectLayer"

func terrain(id: int) -> EcsTerrainDef:
	for def in terrains:
		if def.id == id:
			return def
	return null

func floor_def(id: int) -> EcsFloorDef:
	for def in floors:
		if def.id == id:
			return def
	return null

func wall(id: int) -> EcsWallDef:
	for def in walls:
		if def.id == id:
			return def
	return null
