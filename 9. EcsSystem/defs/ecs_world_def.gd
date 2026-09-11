class_name EcsWorldDef
extends Resource

## The placement list — one world, authored as data. Blueprints live in the
## catalog; this file only says what goes where.

## Every entity in this world, one row each.
@export var entries: Array[EcsPlacement] = []
