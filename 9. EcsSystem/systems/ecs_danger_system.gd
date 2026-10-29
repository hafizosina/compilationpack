class_name EcsDangerSystem
extends EcsSystem

## Fills danger while a threat (EcsHunting.threatens) is in sight, jumps it on an
## EcsHurtFlag, and decays it otherwise. Clears every EcsHurtFlag it has read, and
## those on entities with no danger to raise.

func label() -> StringName:
	return &"danger"

func run(world: EcsWorld, delta: float) -> void:
	var wary := world.view([EcsDangerComponent, EcsPositionComponent], [EcsDyingFlag])
	var dangers := wary.column(EcsDangerComponent)
	var places := wary.column(EcsPositionComponent)
	for k in wary.ids.size():
		var id := wary.ids[k]
		var danger := dangers[k] as EcsDangerComponent
		var here := (places[k] as EcsPositionComponent).position
		var threat := _nearest_threat(world, id, here)
		if threat != EcsWorld.NO_ENTITY:
			danger.value += danger.fill * delta
			_remember(world, danger, threat)
		else:
			danger.value -= danger.decay * delta
		var hurt := world.get_component(id, EcsHurtFlag) as EcsHurtFlag
		if hurt != null:
			danger.value += danger.hit_jump
			if world.has(hurt.by, EcsPositionComponent):
				_remember(world, danger, hurt.by)
			world.remove(id, EcsHurtFlag)
		danger.value = clampf(danger.value, 0.0, 1.0)
	for id in world.query([EcsHurtFlag], [EcsDangerComponent]):
		world.remove(id, EcsHurtFlag)

func _nearest_threat(world: EcsWorld, id: int, here: Vector2) -> int:
	var sensor := world.get_component(id, EcsSensorComponent) as EcsSensorComponent
	if sensor == null:
		return EcsWorld.NO_ENTITY
	var best := EcsWorld.NO_ENTITY
	var best_distance := INF
	for seen in sensor.perceived:
		if not EcsHunting.threatens(world, seen, id):
			continue
		var there := (world.get_component(seen, EcsPositionComponent) as EcsPositionComponent).position
		var distance := here.distance_squared_to(there)
		if distance < best_distance:
			best_distance = distance
			best = seen
	return best

func _remember(world: EcsWorld, danger: EcsDangerComponent, threat: int) -> void:
	danger.threat = threat
	danger.threat_at = (world.get_component(threat, EcsPositionComponent) as EcsPositionComponent).position
