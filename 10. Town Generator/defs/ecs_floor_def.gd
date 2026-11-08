class_name EcsFloorDef
extends EcsTileDef

## A laid floor over the terrain: planks, stone, road, rug.

## What a step onto it costs a walker, in place of the terrain's under it; 0 can't be walked.
@export var walk_cost: float = 1.0
