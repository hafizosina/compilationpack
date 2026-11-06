class_name EcsLookComponent
extends EcsComponent

## How the entity looks as an authored scene (animations, effects, several sprites),
## instanced under its container. A view only: nothing reads game state back off it.

const NODE_KIND: StringName = EcsConst.NODE_LOOK

## Scene whose root is a Node2D, built in the editor.
@export var node_scene: PackedScene

func key() -> StringName:
	return &"look"

func describe() -> Dictionary:
	return {"tab": &"hidden", "lines": {}}
