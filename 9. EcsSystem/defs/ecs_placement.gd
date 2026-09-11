class_name EcsPlacement
extends Resource

## One explicitly placed entity in an EcsWorldDef. References a blueprint by
## `type` and says only what is unique to this instance.

## Name for the spawned entity, stored as its EcsNameComponent. Blank falls back
## to "<type>_<serial>". Authored relationships (a wielded weapon) point at this.
@export var entity_name: StringName = &""
## Blueprint id to spawn, looked up in the EcsEntityCatalog.
@export var type: StringName = &""
## World position to spawn at.
@export var position: Vector2 = Vector2.ZERO
## Per-instance tweaks, keyed by component key:
## `{ "wander": { "radius": 200.0 } }`. Applied to this entity's own copy of the
## component, so it never leaks to the other instances of the type.
@export var overrides: Dictionary = {}
