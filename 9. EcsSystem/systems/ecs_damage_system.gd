class_name EcsDamageSystem
extends EcsSystem

## Applies this tick's hits to their targets' health, less armour, raises
## EcsHurtFlag on each target, then clears the inbox. Death at zero health is
## EcsHealthSystem's.

func label() -> StringName:
	return &"damage"

func run(world: EcsWorld, _delta: float) -> void:
	var combat := world.get_singleton(EcsCombatSingleton) as EcsCombatSingleton
	if combat == null:
		return
	for hit in combat.hits:
		var health := world.get_component(hit.to, EcsHealthComponent) as EcsHealthComponent
		if health == null:
			continue
		var taken := hit.amount
		var armor := world.get_component(hit.to, EcsArmorComponent) as EcsArmorComponent
		if armor != null:
			taken = maxf(taken - armor.reduction, armor.minimum)
		health.value = maxf(health.value - taken, 0.0)
		var hurt := world.get_component(hit.to, EcsHurtFlag) as EcsHurtFlag
		if hurt == null:
			hurt = world.add(hit.to, EcsHurtFlag.new()) as EcsHurtFlag
		hurt.by = hit.from
	combat.hits.clear()
