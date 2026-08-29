class_name SimWorldDef
extends Resource

## The placement list — one world, authored as data. Blueprints live in the
## SimEntityCatalog; this file only says what goes where.

## Every entity in this world, one row each: type, position and any
## per-instance overrides. Distribution is authored here rather than generated —
## a placement algorithm can write this list, but the factory only reads it.
@export var entries: Array[SimPlacement] = []
