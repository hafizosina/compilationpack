class_name EcsCritChanceComponent
extends EcsComponent

## Chance for the wielder's hit to land critically. Read only by EcsCritSystem,
## which sits between the attack and damage stages and scales the damage event
## in flight. The other half of the acceptance test: neither the attack system
## nor the damage system mentions crits, so this component was added to the
## pipeline by scheduling one system and touching nothing else.

@export_range(0.0, 1.0, 0.01) var chance: float = 0.35
@export var multiplier: float = 2.5

func key() -> StringName:
	return &"crit_chance"
