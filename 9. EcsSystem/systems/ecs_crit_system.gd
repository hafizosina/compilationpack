class_name EcsCritSystem
extends EcsSystem

## Scales a hit in flight when the attacker rolls a crit. It sits between the
## attack and damage stages and is the cheapest possible proof of the rule this
## rewrite exists for: crits were added to the pipeline by writing this file and
## appending one line to the scheduler. EcsAttackSystem does not mention crits.
## EcsDamageSystem does not mention crits. Neither was edited.
##
## Toggle it off at runtime (F2) and the pipeline keeps working, minus crits.

func label() -> StringName:
	return &"crit"

func run(world: EcsWorld, _delta: float) -> void:
	for event: EcsDamageEvent in world.events(EcsDamageEvent):
		var crit := world.get_component(event.from, EcsCritChanceComponent) as EcsCritChanceComponent
		if crit == null:
			continue
		if randf() >= crit.chance:
			continue
		event.amount *= crit.multiplier
		event.critical = true
