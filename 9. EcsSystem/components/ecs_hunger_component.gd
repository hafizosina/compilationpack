class_name EcsHungerComponent
extends EcsComponent

## How fed it is. `fullness` starts full and drains to zero, which is starving.

## Fullness lost per second while awake.
@export var drain: float = 2.0
## Fraction of `drain` while asleep. Keep above 0 or hunger can't wake a sleeper.
@export var asleep_drain_scale: float = 0.4
## Full.
@export var max_fullness: float = 100.0
## Below this it goes looking for food.
@export var forage_below: float = 65.0
## Below this it eats food within reach. Lower than `forage_below` for a
## carrier (gather now, eat later), higher for a grazer (eat where it lies).
@export var eat_below: float = 40.0
## Health lost per second at zero fullness.
@export var starve_damage: float = 5.0
## Above this, health regenerates.
@export var heal_above: float = 70.0
## Health regained per second above `heal_above`.
@export var heal_rate: float = 1.5

## Current fullness.
var fullness: float = 100.0

func key() -> StringName:
	return &"hunger"

func describe() -> Dictionary:
	return {"tab": &"entity",
		"lines": {"fullness": "%d/%d" % [roundi(fullness), roundi(max_fullness)]}}
