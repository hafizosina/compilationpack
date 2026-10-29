class_name EcsCritChanceComponent
extends EcsComponent

## A chance for each hit it lands to do extra damage.

## Chance per hit, 0 to 1.
@export_range(0.0, 1.0) var chance: float = 0.2
## Damage multiplier on a critical hit.
@export var multiplier: float = 2.0

func key() -> StringName:
	return &"crit_chance"
