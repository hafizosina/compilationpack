class_name EcsDamageComponent
extends EcsComponent

## A natural attack: how hard it hits and how often.

## Damage per hit, before the target's armour.
@export var damage: float = 10.0
## Seconds between hits.
@export var interval: float = 1.2

## Seconds until it can hit again.
var cooldown: float = 0.0

func key() -> StringName:
	return &"damage"
