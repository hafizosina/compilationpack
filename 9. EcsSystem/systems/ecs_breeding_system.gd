class_name EcsBreedingSystem
extends EcsSystem

## Decides who is ready to breed (EcsReadyFlag) and carries out EcsMateIntentFlag: a
## ready pair of one kind, in reach, makes `litter` newborns between them, and both pay
## and wait out their cooldown. One intent at a time, so a pair asking together breeds
## once.

## Most of one kind there may be; past it nobody of that kind is ready. A guard, not a
## balance: food, water and hunters are meant to keep the count.
const SAFETY_CAP: int = 100

func label() -> StringName:
	return &"breeding"

func run(world: EcsWorld, delta: float) -> void:
	var counts := {}
	var named := world.view([EcsNameComponent, EcsBreedingComponent], [EcsDyingFlag])
	var names := named.column(EcsNameComponent)
	for k in named.ids.size():
		var type := (names[k] as EcsNameComponent).type_id
		counts[type] = counts.get(type, 0) + 1

	var breeders := named.column(EcsBreedingComponent)
	for k in named.ids.size():
		var id := named.ids[k]
		var breeding := breeders[k] as EcsBreedingComponent
		if not breeding.rolled:
			breeding.cooldown_left = randf_range(0.0, breeding.cooldown)
			breeding.rolled = true
		breeding.cooldown_left = maxf(breeding.cooldown_left - delta, 0.0)
		var ready: bool = breeding.cooldown_left <= 0.0 \
			and counts[(names[k] as EcsNameComponent).type_id] < SAFETY_CAP \
			and _fed(world, id, breeding)
		if ready != world.has(id, EcsReadyFlag):
			if ready:
				world.add(id, EcsReadyFlag.new())
			else:
				world.remove(id, EcsReadyFlag)

	var inbox := world.get_singleton(EcsLifecycleSingleton) as EcsLifecycleSingleton
	for id in world.query([EcsMateIntentFlag, EcsBreedingComponent], [EcsDyingFlag]):
		var partner := (world.get_component(id, EcsMateIntentFlag) as EcsMateIntentFlag).target_id
		if inbox == null or not _can_mate(world, id, partner):
			continue
		var here := (world.get_component(id, EcsPositionComponent) as EcsPositionComponent).position
		var there := (world.get_component(partner, EcsPositionComponent) as EcsPositionComponent).position
		var mine := world.get_component(id, EcsBreedingComponent) as EcsBreedingComponent
		for i in mine.litter:
			var note := EcsSpawnRequest.new()
			note.type_id = (world.get_component(id, EcsNameComponent) as EcsNameComponent).type_id
			note.position = (here + there) * 0.5
			inbox.spawn_requests.append(note)
		for parent in [id, partner]:
			_pay(world, parent)

## Fullness and hydration at or above `ready_above` of their max.
static func _fed(world: EcsWorld, id: int, breeding: EcsBreedingComponent) -> bool:
	var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent
	if hunger != null and hunger.fullness < hunger.max_fullness * breeding.ready_above:
		return false
	var thirst := world.get_component(id, EcsThirstComponent) as EcsThirstComponent
	return thirst == null or thirst.hydration >= thirst.max_hydration * breeding.ready_above

## Both ready, alive, one kind, and the partner in reach.
static func _can_mate(world: EcsWorld, id: int, partner: int) -> bool:
	if id == partner or not world.is_alive(partner) or world.has(partner, EcsDyingFlag):
		return false
	if not world.has(id, EcsReadyFlag) or not world.has(partner, EcsReadyFlag):
		return false
	var a := world.get_component(id, EcsNameComponent) as EcsNameComponent
	var b := world.get_component(partner, EcsNameComponent) as EcsNameComponent
	if a == null or b == null or a.type_id != b.type_id:
		return false
	var action := world.get_component(id, EcsActionComponent) as EcsActionComponent
	return action != null and action.reached.has(partner)

static func _pay(world: EcsWorld, id: int) -> void:
	var breeding := world.get_component(id, EcsBreedingComponent) as EcsBreedingComponent
	breeding.cooldown_left = breeding.cooldown
	var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent
	if hunger != null:
		hunger.fullness = maxf(hunger.fullness - breeding.cost, 0.0)
	var thirst := world.get_component(id, EcsThirstComponent) as EcsThirstComponent
	if thirst != null:
		thirst.hydration = maxf(thirst.hydration - breeding.cost, 0.0)
	world.remove(id, EcsReadyFlag)
