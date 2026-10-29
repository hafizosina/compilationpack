class_name EcsCombatSingleton
extends EcsSingleton

## This tick's hits. EcsAttackSystem adds them, EcsCritSystem may raise them,
## EcsDamageSystem applies them and clears the list.

var hits: Array[EcsHit] = []

func key() -> StringName:
	return &"combat"
