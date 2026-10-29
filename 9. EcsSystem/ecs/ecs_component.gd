class_name EcsComponent
extends Resource

## Base for every component. Components hold data only; behaviour lives in systems.
##
## Exceptions:
## - `key()`: a stable name for the type, used by .tres overrides and labels.
## - `describe()`: optional, display only. Returns
##   `{"tab": &"entity" | &"own" | &"hidden", "lines": {label: text}, "title"?: {name, type}}`
##   for the inspector. Without it the inspector lists every field.
## - `const NODE_KIND`: optional. Names a node kind from EcsConst that
##   EcsEntityManager builds for the entity.

## Stable name for this component kind. Override in every subclass.
func key() -> StringName:
	return &""
