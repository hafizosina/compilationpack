class_name EcsHunting
extends RefCounted

## Who may hunt whom, from diet and power. Read-only over components; there is
## no prey tag, so anything weaker can be prey and anything stronger a threat.

## How strong `id` is. The one place power is read, so it can become derived.
static func power_of(world: EcsWorld, id: int) -> float:
	var health := world.get_component(id, EcsHealthComponent) as EcsHealthComponent
	return health.power if health != null else 0.0

## Can `hunter` hunt `prey`? It eats meat and can attack; the prey is alive,
## somewhere, not dying and weaker.
static func can_hunt(world: EcsWorld, hunter: int, prey: int) -> bool:
	if hunter == prey or not world.has(hunter, EcsDamageComponent):
		return false
	var hunger := world.get_component(hunter, EcsHungerComponent) as EcsHungerComponent
	if hunger == null or hunger.eats != &"meat":
		return false
	if not world.has(prey, EcsHealthComponent) or not world.has(prey, EcsPositionComponent) \
			or world.has(prey, EcsDyingFlag):
		return false
	return power_of(world, prey) < power_of(world, hunter)

## Is `other` a danger to `id`? Anything that could hunt it.
static func threatens(world: EcsWorld, other: int, id: int) -> bool:
	return can_hunt(world, other, id)
