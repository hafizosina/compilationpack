class_name EcsDurabilityComponent
extends EcsComponent

## Wear on a wielded item. This is the component module 8 could not house
## cleanly: there, a carried item was a de-noded resource with no live place to
## keep changing state. Here the weapon is an ordinary entity id, and the
## durability system queries this table like any other — nobody reaches into
## the item, and nothing about it is special.

@export var max_durability: float = 20.0
@export var current: float = 20.0
## Wear taken per hit landed.
@export var loss_per_hit: float = 1.0

func key() -> StringName:
	return &"durability"
