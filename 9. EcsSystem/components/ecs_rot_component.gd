class_name EcsRotComponent
extends EcsComponent

## Rots away after `lasts` seconds. EcsRotSystem flags it dying then.

## Seconds before it is gone.
@export var lasts: float = 40.0

## Seconds it has existed.
var age: float = 0.0

func key() -> StringName:
	return &"rot"
