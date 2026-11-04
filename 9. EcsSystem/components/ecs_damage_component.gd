class_name EcsDamageComponent
extends EcsComponent

## A natural attack: how hard it hits and how often.

## Damage per hit, before the target's armour.
@export var damage: float = 10.0
## Seconds between hits.
@export var interval: float = 1.2
## Chance per hit of a critical, 0 to 1.
@export_range(0.0, 1.0) var crit_chance: float = 0.0
## Damage multiplier on a critical hit.
@export var crit_multiplier: float = 2.0
## Health per second a hit makes the target bleed; 0 for none.
@export var bleed_rate: float = 0.0
## Seconds the bleeding lasts.
@export var bleed_for: float = 0.0
## Health per second a hit poisons the target for; 0 for none.
@export var poison_rate: float = 0.0
## Seconds the poison lasts.
@export var poison_for: float = 0.0

## Seconds until it can hit again.
var cooldown: float = 0.0

func key() -> StringName:
	return &"damage"
