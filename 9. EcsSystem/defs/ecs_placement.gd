class_name EcsPlacement
extends Resource

## One placed entity in an EcsWorldDef.

## Name for the spawned entity. Blank means "<type>_<serial>".
@export var entity_name: StringName = &""
## Blueprint id to spawn, looked up in the EcsEntityCatalog.
@export var type: StringName = &""
## World position to spawn at.
@export var position: Vector2 = Vector2.ZERO
## Per-instance overrides, keyed by component key: `{ "wander": { "radius": 200.0 } }`.
@export var overrides: Dictionary = {}
