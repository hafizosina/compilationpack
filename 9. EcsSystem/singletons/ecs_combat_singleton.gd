class_name EcsCombatSingleton
extends EcsSingleton

## Hits not yet applied. EcsAttackSystem adds them, EcsHealthSystem applies them
## and clears the list.

var hits: Array[EcsHit] = []

func key() -> StringName:
	return &"combat"
