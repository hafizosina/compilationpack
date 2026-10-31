class_name EcsDashSkill
extends EcsSkillDef

## A short burst of speed.

## Speed multiplier while dashing.
@export var speed_scale: float = 3.0
## How close prey must be for a dash to be worth it.
@export var reach: float = 180.0
## Seconds a hit landed while dashing stuns its target.
@export var stun: float = 0.0

func make_effect() -> EcsFlag:
	var dashing := EcsDashingFlag.new()
	dashing.speed_scale = speed_scale
	return dashing
