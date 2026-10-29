class_name EcsHealthComponent
extends EcsComponent

## Health. At zero, EcsHealthSystem flags the entity dying.

## Full health.
@export var max_health: float = 100.0

## Current health.
@export var value: float = 100.0

func key() -> StringName:
	return &"health"

func describe() -> Dictionary:
	return {"tab": &"entity",
		"lines": {"health": "%d/%d" % [roundi(value), roundi(max_health)]}}
