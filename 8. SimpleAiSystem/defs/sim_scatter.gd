class_name SimScatter
extends Resource

## A bulk placement rule: "N of this type, randomly inside this area". Expanded
## by SimEntityFactory at spawn time so a 30-entity world stays a six-row file.
## Changing `count` is a one-field edit — no new rows, no code.

## Blueprint id to spawn, looked up in the SimEntityCatalog.
@export var type: StringName = &""
## How many to place.
@export var count: int = 1
## Region to scatter within, in world space.
@export var area: Rect2 = SimConst.WORLD_BOUNDS
## Fixed RNG seed so a given world file always scatters identically. Named
## `rng_seed` because `seed` is a built-in GDScript function.
@export var rng_seed: int = 0
## Overrides applied to every entity this rule places (same shape as
## SimPlacement.overrides).
@export var overrides: Dictionary = {}
