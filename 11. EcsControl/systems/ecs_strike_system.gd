class_name EcsStrikeSystem
extends EcsSystem

## Executes EcsStrikeFlag once: a hit on every reached entity with health inside its arc
## around the facing, the attacker's damage times its scale, crit rolled as an attack. Starts
## the skill's swing.

func label() -> StringName:
	return &"strike"

func run(world: EcsWorld, _delta: float) -> void:
	var combat := world.get_singleton(EcsCombatSingleton) as EcsCombatSingleton
	if combat == null:
		return
	for id in world.query([EcsStrikeFlag, EcsDamageComponent, EcsActionComponent, EcsPositionComponent], [EcsDyingFlag]):
		var strike := world.get_component(id, EcsStrikeFlag) as EcsStrikeFlag
		if strike.struck:
			continue
		strike.struck = true
		var attack := world.get_component(id, EcsDamageComponent) as EcsDamageComponent
		var here := (world.get_component(id, EcsPositionComponent) as EcsPositionComponent).position
		var facing := _facing(world, id)
		for other in (world.get_component(id, EcsActionComponent) as EcsActionComponent).reached:
			if not world.has(other, EcsHealthComponent) or world.has(other, EcsDyingFlag):
				continue
			var to := (world.get_component(other, EcsPositionComponent) as EcsPositionComponent).position - here
			if strike.arc < 360.0 and to != Vector2.ZERO and rad_to_deg(absf(facing.angle_to(to))) > strike.arc * 0.5:
				continue
			var hit := EcsHit.new()
			hit.from = id
			hit.to = other
			hit.amount = attack.damage * strike.damage_scale
			if randf() < attack.crit_chance:
				hit.amount *= attack.crit_multiplier
				hit.critical = true
			combat.hits.append(hit)
		if world.has(id, EcsWeaponComponent):
			if world.has(id, EcsSwingFlag):
				world.remove(id, EcsSwingFlag)
			var swing := EcsSwingFlag.new()
			swing.direction = facing.angle()
			swing.arc = maxf(strike.arc, 60.0)
			swing.duration = strike.swing_time
			world.add(id, swing)

func _facing(world: EcsWorld, id: int) -> Vector2:
	var player := world.get_component(id, EcsPlayerComponent) as EcsPlayerComponent
	return player.facing if player != null else Vector2.RIGHT
