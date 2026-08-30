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

## The component def occupying `wanted_slot`, or null. This is how "capability =
## component presence" is asked of a blueprint rather than of a live entity —
## a stored snapshot is food because its component list contains a food def.
func component_def(wanted_slot: StringName) -> SimComponentDef:
	for def in components:
		if def != null and def.slot() == wanted_slot:
			return def
	return null

func has_component_def(wanted_slot: StringName) -> bool:
	return component_def(wanted_slot) != null

## The first component def offering `verb`, or null. Lets a holder ask what it
## can do with a carried snapshot without knowing what the snapshot is.
func find_with_stub(verb: StringName) -> SimComponentDef:
	for def in components:
		if def != null and verb in def.stubs():
			return def
	return null

func offers(verb: StringName) -> bool:
	return find_with_stub(verb) != null
