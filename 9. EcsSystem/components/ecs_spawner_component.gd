class_name EcsSpawnerComponent
extends EcsComponent

## Periodically spawns an entity nearby, like a bush dropping berries.

## Blueprint id to spawn.
@export var spawns: StringName = &"berry"
## Spawns land within this radius.
@export var radius: float = 260.0
## Seconds between spawns.
@export var interval: float = 2.0
## Most of its spawns that may be on the ground at once.
@export var max_loose: int = 12

## Seconds until the next spawn.
var cooldown: float = 0.0
## Spawn requests not yet fulfilled.
var pending: Array[EcsSpawnRequest] = []
## Ids of its spawns that are still alive.
var spawned: Array[int] = []

func key() -> StringName:
	return &"spawner"
