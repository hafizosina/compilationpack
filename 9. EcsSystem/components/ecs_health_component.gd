class_name EcsHealthComponent
extends EcsComponent

## Health. Only EcsHealthSystem changes `value`, and flags the entity dying at zero.

## Full health.
@export var max_health: float = 100.0

## How strong it is. Only something stronger that eats meat may hunt it.
@export var power: float = 10.0

## Current health.
@export var value: float = 100.0

func key() -> StringName:
	return &"health"

func describe() -> Dictionary:
	return {"tab": &"entity", "lines": {},
		"bars": [{"label": "health", "value": value, "max": max_health, "tone": &"health"}]}
