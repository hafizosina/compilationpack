class_name EcsThirstSystem
extends EcsSystem

## Drains hydration (slower while asleep or collapsed). At zero it raises
## EcsDehydratingFlag, which EcsHealthSystem applies.

func label() -> StringName:
	return &"thirst"

func run(world: EcsWorld, delta: float) -> void:
	var bars := world.view([EcsThirstComponent])
	var thirsts := bars.column(EcsThirstComponent)
	for k in bars.ids.size():
		var id := bars.ids[k]
		var thirst := thirsts[k] as EcsThirstComponent
		# Slower while asleep; must match EcsEnergySystem's idea of asleep.
		var drain := thirst.drain
		if world.has(id, EcsCollapsedFlag) or world.has(id, EcsAsleepFlag):
			drain *= thirst.asleep_drain_scale
		thirst.hydration = maxf(thirst.hydration - drain * delta, 0.0)

	var bodies := world.view([EcsThirstComponent, EcsHealthComponent])
	thirsts = bodies.column(EcsThirstComponent)
	for k in bodies.ids.size():
		var thirst := thirsts[k] as EcsThirstComponent
		EcsHungerSystem.mark(world, bodies.ids[k], EcsDehydratingFlag,
			thirst.hydration <= 0.0, -thirst.dehydrate_damage)
