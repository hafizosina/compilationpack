class_name EcsStrikeSkill
extends EcsSkillDef

## An attack skill: one strike at everything in reach inside an arc around the facing, with
## its own swing. `duration` should match `swing_time`.

## Damage per hit, times the attacker's EcsDamageComponent.damage.
@export var damage_scale: float = 1.5
## Degrees around the facing it hits; 360 is all around.
@export var arc: float = 120.0
## Seconds its swing takes.
@export var swing_time: float = 0.25

func make_effect() -> EcsFlag:
	var strike := EcsStrikeFlag.new()
	strike.damage_scale = damage_scale
	strike.arc = arc
	strike.swing_time = swing_time
	return strike
