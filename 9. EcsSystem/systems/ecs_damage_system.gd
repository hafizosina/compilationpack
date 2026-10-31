class_name EcsDamageSystem
extends EcsSystem

## Applies this tick's hits to their targets' health, less armour, raises
## EcsHurtFlag on each target and EcsStunnedFlag for a stunning hit, then clears the
## inbox. Counts stuns down. Death at zero health is EcsHealthSystem's.

func label() -> StringName:
	return &"damage"

func run(world: EcsWorld, delta: float) -> void:
	for id in world.query([EcsStunnedFlag]):
		var stunned := world.get_component(id, EcsStunnedFlag) as EcsStunnedFlag
		stunned.left -= delta
		if stunned.left <= 0.0:
			world.remove(id, EcsStunnedFlag)

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
		if hit.stun > 0.0:
			var stunned := world.get_component(hit.to, EcsStunnedFlag) as EcsStunnedFlag
			if stunned == null:
				stunned = world.add(hit.to, EcsStunnedFlag.new()) as EcsStunnedFlag
			stunned.left = maxf(stunned.left, hit.stun)
	combat.hits.clear()
