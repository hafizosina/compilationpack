class_name EcsCoverComponent
extends EcsComponent

## A place to hide in, like water. In cover means its body is in the hider's reach.

## How well it hides, 0 to 1.
@export_range(0.0, 1.0) var conceal: float = 1.0

func key() -> StringName:
	return &"cover"
