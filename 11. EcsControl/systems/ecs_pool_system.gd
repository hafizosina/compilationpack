class_name EcsPoolSystem
extends EcsSystem

## The only writer of stamina and mana: pays what was asked for, and refills a pool that
## hasn't been spent for its `regen_delay`.

func label() -> StringName:
	return &"pool"

func run(world: EcsWorld, delta: float) -> void:
	for kind: Script in [EcsStaminaComponent, EcsManaComponent]:
		for id in world.query([kind]):
			var pool := world.get_component(id, kind) as EcsPoolComponent
			if pool.spent > 0.0:
				pool.value = maxf(pool.value - pool.spent, 0.0)
				pool.spent = 0.0
				pool.since_spent = 0.0
				continue
			pool.since_spent += delta
			if pool.since_spent >= pool.regen_delay:
				pool.value = minf(pool.value + pool.regen * delta, pool.max_value)
