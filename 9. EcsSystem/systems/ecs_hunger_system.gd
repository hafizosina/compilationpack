class_name EcsHungerSystem
extends EcsSystem

## Drains fullness (slower while asleep or collapsed). At zero it costs health;
## above `heal_above` health regenerates.

func label() -> StringName:
	return &"hunger"

func run(world: EcsWorld, delta: float) -> void:
	var bars := world.view([EcsHungerComponent])
	var hungers := bars.column(EcsHungerComponent)
	for k in bars.ids.size():
		var id := bars.ids[k]
		var hunger := hungers[k] as EcsHungerComponent
		# Slower while asleep; must match EcsEnergySystem's idea of asleep.
		var drain := hunger.drain
		if world.has(id, EcsCollapsedFlag) or world.has(id, EcsAsleepFlag):
			drain *= hunger.asleep_drain_scale
		hunger.fullness = maxf(hunger.fullness - drain * delta, 0.0)

	# Second pass: only entities that also have health.
	var bodies := world.view([EcsHungerComponent, EcsHealthComponent])
	hungers = bodies.column(EcsHungerComponent)
	var healths := bodies.column(EcsHealthComponent)
	for k in bodies.ids.size():
		var hunger := hungers[k] as EcsHungerComponent
		var health := healths[k] as EcsHealthComponent
		if hunger.fullness <= 0.0:
			health.value = maxf(health.value - hunger.starve_damage * delta, 0.0)
		elif hunger.fullness >= hunger.heal_above:
			health.value = minf(health.value + hunger.heal_rate * delta, health.max_health)
