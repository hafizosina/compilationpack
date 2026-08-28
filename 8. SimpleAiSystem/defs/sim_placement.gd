class_name SimPlacement
extends Resource

## One explicitly placed entity in a SimWorldDef. References a blueprint by
## `type` and specifies only what is unique to this instance.

## Node name for the spawned entity. Blank falls back to "<type>_<serial>".
@export var entity_name: String = ""
## Blueprint id to spawn, looked up in the SimEntityCatalog.
@export var type: StringName = &""
## World position to spawn at.
@export var position: Vector2 = Vector2.ZERO
## Per-instance tweaks, keyed by component slot:
## `{ "wander": { "radius": 48.0 } }`. Applied to this entity's own duplicated
## def before the component is built, so it never leaks to other instances.
@export var overrides: Dictionary = {}
