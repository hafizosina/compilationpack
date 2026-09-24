class_name EcsHungerSystem
extends EcsSystem

## Fullness drains; running empty costs health and being well fed mends it.
##
## One loop, one field, the ECS-native version of a self-ticking bar: the
## component is the reading and this is the clock. Module 8 would have put a
## `_process` on the bar itself and let each creature tick its own; here 4,000
## creatures are one query and one multiply.
##
## It writes health as well as hunger, which is worth being clear about. That is
## not this system reaching into another's business — **what being empty or full
## does to you is hunger's rule**, so both halves live with hunger, and what
## happens when health runs out is EcsHealthSystem's rule and lives there. Each
## system owns the consequences of the component it is named for, and neither
## has to know the other exists.
##
## Regeneration was argued against while starvation was the only damage source,
## on the grounds that it would simply undo it. Gating it on `heal_above` is
## what answers that: mending is not the absence of starving, it is the reward
## for having eaten, and the band between the two thresholds is a creature that
## is neither getting better nor worse.
##
## An entity with no EcsHealthComponent starves forever without dying. That is
## not a special case in here; it is the absence of one.

func label() -> StringName:
	return &"hunger"

func run(world: EcsWorld, delta: float) -> void:
	for id in world.query([EcsHungerComponent]):
		var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent
		hunger.fullness = maxf(hunger.fullness - hunger.drain * delta, 0.0)

		var health := world.get_component(id, EcsHealthComponent) as EcsHealthComponent
		if health == null:
			# Nothing to spend or mend. It starves forever, and that is not a
			# special case in here — it is the absence of one.
			continue
		if hunger.fullness <= 0.0:
			# Empty, with nothing left to draw on, so it starts costing.
			health.value = maxf(health.value - hunger.starve_damage * delta, 0.0)
		elif hunger.fullness >= hunger.heal_above:
			health.value = minf(health.value + hunger.heal_rate * delta, health.max_health)
