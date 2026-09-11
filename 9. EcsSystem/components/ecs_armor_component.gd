class_name EcsArmorComponent
extends EcsComponent

## Flat damage reduction on the defender. Read by exactly one system — the
## damage system — which is the whole acceptance test for this rewrite: adding
## armour to an entity changes no attack code, because the attack side never
## learns that armour exists.

## Points subtracted from each incoming hit.
@export var reduction: float = 4.0
## Floor, so armour blunts a hit but never makes an entity untouchable.
@export var minimum: float = 1.0

func key() -> StringName:
	return &"armor"
