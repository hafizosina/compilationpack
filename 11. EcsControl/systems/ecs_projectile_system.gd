class_name EcsProjectileSystem
extends EcsSystem

## Steers each projectile along its direction, and when it reaches something with health that
## isn't its owner, hits it and ends (cause removed, detail &"impact", so its remains can burst).

func label() -> StringName:
	return &"projectile"

func run(world: EcsWorld, _delta: float) -> void:
	var combat := world.get_singleton(EcsCombatSingleton) as EcsCombatSingleton
	if combat == null:
		return
	for id in world.query([EcsProjectileComponent, EcsMovementComponent, EcsActionComponent], [EcsDyingFlag]):
		var shot := world.get_component(id, EcsProjectileComponent) as EcsProjectileComponent
		(world.get_component(id, EcsMovementComponent) as EcsMovementComponent).steer = shot.direction
		for other in (world.get_component(id, EcsActionComponent) as EcsActionComponent).reached:
			if other == shot.owner or not world.has(other, EcsHealthComponent) or world.has(other, EcsDyingFlag):
				continue
			var hit := EcsHit.new()
			hit.from = shot.owner if world.is_alive(shot.owner) else id
			hit.to = other
			hit.amount = shot.damage
			combat.hits.append(hit)
			var dying := EcsDyingFlag.new()
			dying.cause = EcsDyingFlag.REMOVED
			dying.detail = &"impact"
			world.add(id, dying)
			break
