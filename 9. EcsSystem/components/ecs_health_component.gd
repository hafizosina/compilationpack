class_name EcsHealthComponent
extends EcsComponent

## Health. Only EcsHealthSystem changes `value`, and flags the entity dying at zero.

## The field that is this bar's current amount; a skill cost reads it.
const BAR_VALUE: StringName = &"value"

## Full health.
@export var max_health: float = 100.0

## How strong it is. Only something stronger that eats meat may hunt it.
@export var power: float = 10.0

## Current health.
@export var value: float = 100.0
## Spending asked for (a skill's cost) and not yet applied; its own system applies it.
var spent: float = 0.0

func key() -> StringName:
	return &"health"

func describe() -> Dictionary:
	return {"tab": &"entity", "lines": {},
		"bars": [{"label": "health", "value": value, "max": max_health, "tone": &"health"}]}
