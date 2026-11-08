class_name EcsResourceNodeComponent
extends EcsComponent

## Something in the world that can be gathered from: a tree, a bush, a rock, an ore vein.

## What kind of node it is (`&"tree"`, `&"ore"`), for whatever gathers from it.
@export var kind: StringName = &""
## What gathering it gives (`&"wood"`, `&"iron_ore"`).
@export var gives: StringName = &""

func key() -> StringName:
	return &"resource_node"
