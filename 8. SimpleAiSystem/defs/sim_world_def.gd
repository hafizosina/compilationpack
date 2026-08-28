class_name SimWorldDef
extends Resource

## The placement list — one world, authored as data. Blueprints live in the
## SimEntityCatalog; this file only says what goes where.

## Explicitly placed entities. Use these for anything whose position matters or
## that carries a per-instance override.
@export var entries: Array[SimPlacement] = []
## Bulk scatter rules, expanded after `entries`. Use these for filler population.
@export var scatters: Array[SimScatter] = []
