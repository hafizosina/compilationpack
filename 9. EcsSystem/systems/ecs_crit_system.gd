class_name EcsCritSystem
extends EcsSystem

## Rolls each hit against its attacker's EcsCritChanceComponent and multiplies
## the ones that crit.

func label() -> StringName:
	return &"crit"

func run(world: EcsWorld, _delta: float) -> void:
	var combat := world.get_singleton(EcsCombatSingleton) as EcsCombatSingleton
	if combat == null:
		return
	for hit in combat.hits:
		var crit := world.get_component(hit.from, EcsCritChanceComponent) as EcsCritChanceComponent
		if crit == null or randf() >= crit.chance:
			continue
		hit.amount *= crit.multiplier
		hit.critical = true
