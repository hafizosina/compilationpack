class_name EcsHungerSystem
extends EcsSystem

## Hunger climbs, and starving costs health.
##
## One loop, one field, the ECS-native version of a self-ticking bar: the
## component is the reading and this is the clock. Module 8 would have put a
## `_process` on the bar itself and let each creature tick its own; here 4,000
## creatures are one query and one multiply.
##
## It writes health as well as hunger, which is worth being clear about. That is
## not this system reaching into another's business — **starvation is hunger's
## rule**, so it lives with hunger, and what happens when health runs out is
## EcsHealthSystem's rule and lives there. Each system owns the consequences of
## the component it is named for, and neither has to know the other exists.
##
## An entity with no EcsHealthComponent starves forever without dying. That is
## not a special case in here; it is the absence of one.

func label() -> StringName:
	return &"hunger"

func run(world: EcsWorld, delta: float) -> void:
	for id in world.query([EcsHungerComponent]):
		var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent
		hunger.value = minf(hunger.value + hunger.rate * delta, hunger.max_value)
		if hunger.value < hunger.max_value:
			continue
		# Pinned at the top: nothing left to fill, so it starts costing.
		var health := world.get_component(id, EcsHealthComponent) as EcsHealthComponent
		if health != null:
			health.value = maxf(health.value - hunger.starve_damage * delta, 0.0)
