class_name EcsCoverComponent
extends EcsComponent

## A place to hide in, like water or a bush. In cover means its body is in the hider's reach.

## What kind of cover; a hide skill names the kinds it can use.
@export var kind: StringName = &"bush"
## How well it hides, 0 to 1.
@export_range(0.0, 1.0) var conceal: float = 1.0

func key() -> StringName:
	return &"cover"
