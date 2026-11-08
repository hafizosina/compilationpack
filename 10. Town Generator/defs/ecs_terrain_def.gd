class_name EcsTerrainDef
extends EcsTileDef

## Ground under everything: grass, dirt, sand, water.

## What a step onto it costs a walker; 0 can't be walked. A floor laid over it sets its own.
@export var walk_cost: float = 1.0
