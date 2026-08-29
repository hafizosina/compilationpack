class_name SimEntityDef
extends Resource

## One entity blueprint — the authored answer to "what is a type1?".
## What the thing *is* equals which components this lists. There is no type
## hierarchy and no per-type scene: a new creature is a new .tres.

## Stable lookup id, referenced by SimPlacement.type.
@export var id: StringName = &""
## Human-readable name, shown by the debug overlay and the stats panel.
@export var display_name: String = ""
## The component blueprints that make up this entity. Order is build order.
@export var components: Array[SimComponentDef] = []
