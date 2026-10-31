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

## How noticeable `id` is, 0 to 1, to `watcher` at `here`: 1 unless hidden, then
## 1 - stealth less the watcher's awareness. A scanning watcher sees a hider within
## its scan radius plainly; callers pass only ids the watcher perceives.
static func visibility_of(world: EcsWorld, id: int, watcher: int, here: Vector2) -> float:
	var hidden := world.get_component(id, EcsHiddenFlag) as EcsHiddenFlag
	if hidden == null:
		return 1.0
	var scanning := world.get_component(watcher, EcsScanningFlag) as EcsScanningFlag
	if scanning != null:
		var there := world.get_component(id, EcsPositionComponent) as EcsPositionComponent
		if there != null and here.distance_squared_to(there.position) <= scanning.radius * scanning.radius:
			return 1.0
	var sensor := world.get_component(watcher, EcsSensorComponent) as EcsSensorComponent
	var awareness := sensor.awareness if sensor != null else 0.0
	return 1.0 - hidden.stealth * (1.0 - awareness)

## The best cover `id` has in reach, 0 for none.
static func cover_of(world: EcsWorld, id: int) -> float:
	var action := world.get_component(id, EcsActionComponent) as EcsActionComponent
	if action == null:
		return 0.0
	var best := 0.0
	for touched in action.reached:
		var cover := world.get_component(touched, EcsCoverComponent) as EcsCoverComponent
		if cover != null:
			best = maxf(best, cover.conceal)
	return best

## How close prey must be for `id` to dash at it, 0 if it has no dash.
static func dash_reach(world: EcsWorld, id: int) -> float:
	var known := world.get_component(id, EcsSkillsComponent) as EcsSkillsComponent
	if known != null:
		for skill in known.skills:
			if skill is EcsDashSkill:
				return (skill as EcsDashSkill).reach
	return 0.0

## Is `other` a danger to `id`? Anything that could hunt it.
static func threatens(world: EcsWorld, other: int, id: int) -> bool:
	return can_hunt(world, other, id)
