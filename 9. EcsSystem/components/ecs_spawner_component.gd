class_name EcsSpawnerComponent
extends EcsComponent

## Periodically puts another entity into the world nearby — a berry bush
## dropping berries.
##
## Compare module 8's SimEntitySpawnerComponent, which did this itself in
## `_process` and found the factory through a group lookup. Here the component
## is the *settings*, and EcsSpawnerSystem is the doing. What it spawns is a
## blueprint id, so a spawner produces anything in the catalog with no code
## change — that part module 8 already had right.

## Blueprint id to spawn, looked up in the EcsEntityCatalog.
@export var spawns: StringName = &"berry"
## Spawns land at a random point within this radius of the spawner.
@export var radius: float = 260.0
## Seconds between spawns.
@export var interval: float = 2.0
## Ceiling on how many of this spawner's entities may be lying on the ground at
## once. Without a cap a one-every-two-seconds spawner litters without bound.
##
## It counts *loose* ones, not held ones: a berry in someone's inventory has no
## EcsPositionComponent, so it stops counting here and the bush resumes. Nothing
## tells the spawner a berry was picked up — the same missing component that
## un-renders it also un-counts it.
@export var max_loose: int = 12

## Seconds until the next spawn. Runtime state.
var cooldown: float = 0.0
## Entity ids this spawner has produced and that are still alive.
##
## Module 8 kept node references here and pruned with `is_instance_valid()`.
## Ids are better: they are never reused, so a harvested berry's id goes
## permanently false through `world.is_alive()` and can never be confused with
## a later entity that happens to occupy the same memory.
var spawned: Array[int] = []

func key() -> StringName:
	return &"spawner"
