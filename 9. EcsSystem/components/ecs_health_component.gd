class_name EcsHealthComponent
extends EcsComponent

## Hit points. Carrying this is what makes an entity attackable at all: the
## aggression system's target query asks for Health, so the wandering rabbits —
## which have none — are invisible to it without a single line of special case.

@export var max_hp: float = 60.0
@export var hp: float = 60.0

func key() -> StringName:
	return &"health"
