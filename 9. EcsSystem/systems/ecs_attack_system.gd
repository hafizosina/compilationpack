class_name EcsAttackSystem
extends EcsSystem

## Executes EcsAttackIntentFlag: when the attack is off cooldown and the target
## is alive, unclaimed and in reach, adds a hit to the combat inbox.

func label() -> StringName:
	return &"attack"

func run(world: EcsWorld, delta: float) -> void:
	var combat := world.get_singleton(EcsCombatSingleton) as EcsCombatSingleton
	if combat == null:
		return

	var armed := world.view([EcsDamageComponent])
	var attacks := armed.column(EcsDamageComponent)
	for k in armed.ids.size():
		var attack := attacks[k] as EcsDamageComponent
		attack.cooldown = maxf(attack.cooldown - delta, 0.0)

	for id in world.query([EcsAttackIntentFlag, EcsDamageComponent, EcsActionComponent],
			[EcsDyingFlag]):
		var attack := world.get_component(id, EcsDamageComponent) as EcsDamageComponent
		if attack.cooldown > 0.0:
			continue
		var target := (world.get_component(id, EcsAttackIntentFlag) as EcsAttackIntentFlag).target_id
		if not _can_hit(world, id, target):
			continue
		var hit := EcsHit.new()
		hit.from = id
		hit.to = target
		hit.amount = attack.damage
		combat.hits.append(hit)
		attack.cooldown = attack.interval

func _can_hit(world: EcsWorld, id: int, target: int) -> bool:
	if not world.has(target, EcsHealthComponent) or world.has(target, EcsDyingFlag):
		return false
	var action := world.get_component(id, EcsActionComponent) as EcsActionComponent
	return action.reached.has(target)
