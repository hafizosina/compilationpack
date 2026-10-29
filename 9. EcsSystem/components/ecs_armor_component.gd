class_name EcsArmorComponent
extends EcsComponent

## Reduces the damage of every hit taken.

## Damage taken off each hit.
@export var reduction: float = 3.0
## The least a hit can do after armour.
@export var minimum: float = 1.0

func key() -> StringName:
	return &"armor"
