class_name EcsAggressionSystem
extends EcsSystem

## The placeholder brain: on a timer, swing at the nearest attackable thing in
## reach. Everything it knows how to produce is one EcsAttackIntentComponent.
##
## Note what it does NOT consult: weapons, damage, armour, durability. It cannot
## even tell whether the swing will land. Step 6 swaps this out for an FSM and
## step 7 for a planner, and because all three write the same intent component,
## no system after this one changes by a character.
##
## "Attackable" is not a flag anyone maintains — it is the target query. An
## entity with an EcsHealthComponent can be hit; the wandering rabbits have
## none, so they are invisible here without a special case.

func label() -> StringName:
	return &"aggression"

func run(world: EcsWorld, delta: float) -> void:
	var attackers := world.query([EcsAggressionComponent, EcsPositionComponent], [EcsDeadComponent])
	if attackers.is_empty():
		return
	var targets := world.query([EcsHealthComponent, EcsPositionComponent], [EcsDeadComponent])

	for id in attackers:
		var aggression := world.get_component(id, EcsAggressionComponent) as EcsAggressionComponent
		aggression.cooldown -= delta
		if aggression.cooldown > 0.0:
			continue
		var here := (world.get_component(id, EcsPositionComponent) as EcsPositionComponent).position

		var best := EcsWorld.NO_ENTITY
		var best_distance := aggression.reach * aggression.reach
		for other in targets:
			if other == id:
				continue
			var there := (world.get_component(other, EcsPositionComponent) as EcsPositionComponent).position
			var distance := here.distance_squared_to(there)
			if distance <= best_distance:
				best_distance = distance
				best = other
		if best == EcsWorld.NO_ENTITY:
			continue

		aggression.cooldown = aggression.interval
		var intent := EcsAttackIntentComponent.new()
		intent.target_id = best
		world.add(id, intent)
