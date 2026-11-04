class_name EcsAttachableComponent
extends EcsComponent

## Something that hangs on a wall or sits on furniture, and which of those it may.

@export var on_wall: bool = false
@export var on_furniture: bool = false

func key() -> StringName:
	return &"attachable"
