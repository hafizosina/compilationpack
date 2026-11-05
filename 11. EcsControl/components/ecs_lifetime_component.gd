class_name EcsLifetimeComponent
extends EcsComponent

## Gone after `seconds` (cause removed, detail &"expired").

@export var seconds: float = 1.0

## Seconds lived.
var age: float = 0.0

func key() -> StringName:
	return &"lifetime"
