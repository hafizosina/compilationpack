class_name EcsHungerSystem
extends EcsSystem

## Drains fullness (slower while asleep or collapsed). Raises EcsStarvingFlag at
## zero and EcsMendingFlag while above `heal_above` and hurt; EcsHealthSystem
## applies them.

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

	# Second pass: what fullness does to health, as flags EcsHealthSystem applies.
	var bodies := world.view([EcsHungerComponent, EcsHealthComponent])
	hungers = bodies.column(EcsHungerComponent)
	var healths := bodies.column(EcsHealthComponent)
	for k in bodies.ids.size():
		var id := bodies.ids[k]
		var hunger := hungers[k] as EcsHungerComponent
		var health := healths[k] as EcsHealthComponent
		EcsHungerSystem.mark(world, id, EcsStarvingFlag, hunger.fullness <= 0.0,
			-hunger.starve_damage)
		var mends := hunger.fullness >= hunger.heal_above \
			and health.value > 0.0 and health.value < health.max_health
		EcsHungerSystem.mark(world, id, EcsMendingFlag, mends, hunger.heal_rate)

## Raises `kind` at `rate` on `id` when `on`, and removes it otherwise.
static func mark(world: EcsWorld, id: int, kind: Script, on: bool, rate: float) -> void:
	var effect := world.get_component(id, kind) as EcsHealthOverTimeFlag
	if not on:
		if effect != null:
			world.remove(id, kind)
		return
	if effect == null:
		effect = world.add(id, kind.new()) as EcsHealthOverTimeFlag
	effect.rate = rate
