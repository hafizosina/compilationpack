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

## Visibility below this goes unnoticed by a hunter choosing prey.
const NOTICE_AT: float = 0.5

## Does `hunter` at `here` notice `prey`? Hidden prey it can't see well is passed over.
static func notices(world: EcsWorld, hunter: int, prey: int, here: Vector2) -> bool:
	return visibility_of(world, prey, hunter, here) >= NOTICE_AT

## The best cover `id` has in reach of a kind it can hide in, 0 for none.
static func cover_of(world: EcsWorld, id: int) -> float:
	var action := world.get_component(id, EcsActionComponent) as EcsActionComponent
	var kinds := hide_kinds(world, id)
	if action == null or kinds.is_empty():
		return 0.0
	var best := 0.0
	for touched in action.reached:
		var cover := world.get_component(touched, EcsCoverComponent) as EcsCoverComponent
		if cover != null and kinds.has(cover.kind):
			best = maxf(best, cover.conceal)
	return best

## The cover kinds `id`'s hide skill can use; empty without one.
static func hide_kinds(world: EcsWorld, id: int) -> Array[StringName]:
	return kinds_in(world.get_component(id, EcsSkillsComponent) as EcsSkillsComponent)

## The cover kinds the hide skill in `known` can use; empty without one.
static func kinds_in(known: EcsSkillsComponent) -> Array[StringName]:
	if known != null:
		for skill in known.skills:
			if skill is EcsHideSkill:
				return (skill as EcsHideSkill).kinds
	return []

## Does `id` hide in cover `cover`?
static func hides_in(world: EcsWorld, id: int, cover: int) -> bool:
	var found := world.get_component(cover, EcsCoverComponent) as EcsCoverComponent
	return found != null and hide_kinds(world, id).has(found.kind)

## Is `id` a lure: a place prey must visit, to drink or to harvest?
static func is_lure(world: EcsWorld, id: int) -> bool:
	return world.has(id, EcsDrinkableComponent) or world.has(id, EcsHarvestableComponent)

## Is `id`'s dash ready to cast?
static func dash_ready(world: EcsWorld, id: int) -> bool:
	return dash_ready_in(world.get_component(id, EcsSkillsComponent) as EcsSkillsComponent)

## Is the dash in `known` ready to cast?
static func dash_ready_in(known: EcsSkillsComponent) -> bool:
	if known == null:
		return false
	for skill in known.skills:
		if skill is EcsDashSkill:
			return not known.cooldown_left.has(skill.id) and not known.active_left.has(skill.id)
	return false

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
