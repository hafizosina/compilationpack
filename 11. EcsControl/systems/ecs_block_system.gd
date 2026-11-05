class_name EcsBlockSystem
extends EcsSystem

## Between the hits being made and health applying them: a hit on a guarding entity from inside
## its EcsBlockingFlag's arc loses `reduction` of its damage, and its stun, bleeding and poison.

## Hits blocked in the last run.
var blocked: int = 0

func label() -> StringName:
	return &"block"

func run(world: EcsWorld, _delta: float) -> void:
	blocked = 0
	var combat := world.get_singleton(EcsCombatSingleton) as EcsCombatSingleton
	if combat == null:
		return
	for hit in combat.hits:
		var guard := world.get_component(hit.to, EcsBlockingFlag) as EcsBlockingFlag
		if guard == null:
			continue
		var player := world.get_component(hit.to, EcsPlayerComponent) as EcsPlayerComponent
		var here := world.get_component(hit.to, EcsPositionComponent) as EcsPositionComponent
		var there := world.get_component(hit.from, EcsPositionComponent) as EcsPositionComponent
		if player == null or here == null or there == null:
			continue
		var to := there.position - here.position
		if to != Vector2.ZERO and rad_to_deg(absf(player.facing.angle_to(to))) > guard.arc * 0.5:
			continue
		hit.amount *= 1.0 - guard.reduction
		hit.stun = 0.0
		hit.bleed_rate = 0.0
		hit.poison_rate = 0.0
		blocked += 1
