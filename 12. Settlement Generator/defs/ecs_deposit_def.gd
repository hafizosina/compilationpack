class_name EcsDepositDef
extends Resource

## A kind of deposit a region holds: blobs of ground where one resource node grows. A spawn def
## naming it (`EcsNodeSpawnDef.deposit`) grows only inside one when its map has deposits.

@export var key: StringName = &""
## The ground it lies on, by EcsTerrainGenerator's kind.
@export_enum("grass", "water", "sand", "rock", "forest") var ground: int = 3
## How many blobs a region has, and their radius in region cells.
@export var count: Vector2i = Vector2i(2, 4)
@export var radius: Vector2i = Vector2i(1, 3)
