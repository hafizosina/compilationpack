class_name EcsComponent
extends Resource

## Base for every component. Components hold data only; behaviour lives in systems.
##
## Exceptions:
## - `key()`: a stable name for the type, used by .tres overrides and labels.
## - `describe()`: optional, display only. Returns
##   `{"tab": &"entity" | &"own" | &"hidden", "lines": {label: text}, "title"?: {name, type},
##   "bars"?: [{label, value, max, tone}]}` for the inspector. "entity" lines go to the
##   summary, "own" lines into the component's card. Without it the card lists every field.
## - `const NODE_KIND`: optional. Names a node kind from EcsConst that
##   EcsEntityManager builds for the entity: the `node_scene` field's scene if the
##   component has one set, else a `const NODE_CLASS` engine class, else an area on
##   `NODE_LAYER` / `NODE_MASK`.

## Off means the entity is treated as not having it: queries, `has()` and
## `get_component()` skip it, so no system sees it. It stays on the entity, shown
## in the inspector, and can be switched back on. Flags and singletons ignore it.
@export var enabled: bool = true

## Stable name for this component kind. Override in every subclass.
func key() -> StringName:
	return &""
