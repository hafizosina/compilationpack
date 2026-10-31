class_name EcsScanSkill
extends EcsSkillDef

## Stopping to look hard: anything hidden it perceives within `radius` is seen plainly.

## How near a hider must be to be revealed.
@export var radius: float = 200.0

func make_effect() -> EcsFlag:
	var scanning := EcsScanningFlag.new()
	scanning.radius = radius
	return scanning
