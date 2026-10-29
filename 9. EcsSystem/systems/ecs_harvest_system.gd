class_name EcsHarvestSystem
extends EcsSystem

## Regrows harvestables and executes EcsHarvestIntentFlag: while the target is in
## reach and has stock, each `harvest_time` takes one unit and requests its yield
## on the ground beside the harvester.

func label() -> StringName:
	return &"harvest"

func run(world: EcsWorld, delta: float) -> void:
	var plants := world.view([EcsHarvestableComponent])
	for crop in plants.column(EcsHarvestableComponent):
		_regrow(crop as EcsHarvestableComponent, delta)

	var inbox := world.get_singleton(EcsLifecycleSingleton) as EcsLifecycleSingleton
	if inbox == null:
		return
	for id in world.query([EcsHarvestIntentFlag, EcsActionComponent, EcsPositionComponent],
			[EcsDyingFlag]):
		var intent := world.get_component(id, EcsHarvestIntentFlag) as EcsHarvestIntentFlag
		var plant := intent.target_id
		if not world.is_alive(plant) or world.has(plant, EcsDyingFlag):
			continue
		var crop := world.get_component(plant, EcsHarvestableComponent) as EcsHarvestableComponent
		var action := world.get_component(id, EcsActionComponent) as EcsActionComponent
		if crop == null or crop.stock <= 0 or not action.reached.has(plant):
			continue
		intent.progress += delta
		if intent.progress < crop.harvest_time:
			continue
		intent.progress = 0.0
		crop.stock -= 1
		var here := world.get_component(id, EcsPositionComponent) as EcsPositionComponent
		var note := EcsSpawnRequest.new()
		note.type_id = crop.yields
		note.position = here.position + Vector2.RIGHT.rotated(randf() * TAU) * action.radius * 0.5
		inbox.spawn_requests.append(note)

func _regrow(crop: EcsHarvestableComponent, delta: float) -> void:
	if not crop.stocked:
		crop.stock = crop.stock_max
		crop.stocked = true
	if crop.stock >= crop.stock_max:
		crop.regrow_left = crop.regrow
		return
	crop.regrow_left -= delta
	if crop.regrow_left <= 0.0:
		crop.stock += 1
		crop.regrow_left = crop.regrow
