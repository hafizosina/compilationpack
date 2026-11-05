class_name EcsThornsSystem
extends EcsSystem

## When a thorn's attack is ready, hits everything with health it reaches and starts the
## cooldown. EcsAttackSystem counts the cooldown down, as for every attack.

func label() -> StringName:
	return &"thorns"

func run(world: EcsWorld, _delta: float) -> void:
	var combat := world.get_singleton(EcsCombatSingleton) as EcsCombatSingleton
	if combat == null:
		return
	for id in world.query([EcsThornsComponent, EcsDamageComponent, EcsActionComponent], [EcsDyingFlag]):
		var attack := world.get_component(id, EcsDamageComponent) as EcsDamageComponent
		if attack.cooldown > 0.0:
			continue
		var struck := false
		for other in (world.get_component(id, EcsActionComponent) as EcsActionComponent).reached:
			if other == id or not world.has(other, EcsHealthComponent) or world.has(other, EcsDyingFlag) \
					or world.has(other, EcsThornsComponent):
				continue
			var hit := EcsHit.new()
			hit.from = id
			hit.to = other
			hit.amount = attack.damage
			combat.hits.append(hit)
			struck = true
		if struck:
			attack.cooldown = attack.interval
