class_name EcsBlockSkill
extends EcsSkillDef

## A guard for `duration` seconds: hits from inside `arc` around the facing lose `reduction` of
## their damage, and their stun, bleeding and poison.

## Share of a blocked hit's damage taken away, 0 to 1.
@export_range(0.0, 1.0) var reduction: float = 0.8
## Degrees around the facing it guards.
@export var arc: float = 140.0

func make_effect() -> EcsFlag:
	var blocking := EcsBlockingFlag.new()
	blocking.reduction = reduction
	blocking.arc = arc
	return blocking
