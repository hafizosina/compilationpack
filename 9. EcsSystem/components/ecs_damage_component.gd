class_name EcsDamageComponent
extends EcsComponent

## How hard a hit lands. Lives on the *weapon* entity when one is wielded and on
## the attacker itself for unarmed blows — same component, and the attack system
## reads whichever it finds without either case being special.

@export var amount: float = 6.0

func key() -> StringName:
	return &"damage"
