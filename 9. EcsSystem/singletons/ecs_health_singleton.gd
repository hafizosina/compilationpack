class_name EcsHealthSingleton
extends EcsSingleton

## Instant health changes that aren't hits. EcsHealthSystem applies them and
## clears the list.

var changes: Array[EcsHealthChange] = []

func key() -> StringName:
	return &"health"
