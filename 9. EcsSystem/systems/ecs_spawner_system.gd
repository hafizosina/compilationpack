class_name EcsSpawnerSystem
extends EcsSystem

## Counts down each spawner and requests a new entity when it is due. The
## entity appears at the next lifecycle stage.

func label() -> StringName:
	return &"spawner"

func run(world: EcsWorld, delta: float) -> void:
	var inbox := world.get_singleton(EcsLifecycleSingleton) as EcsLifecycleSingleton
	if inbox == null:
		return

	for id in world.query([EcsPositionComponent, EcsSpawnerComponent]):
		var spawner := world.get_component(id, EcsSpawnerComponent) as EcsSpawnerComponent
		_harvest(spawner)

		spawner.cooldown -= delta
		if spawner.cooldown > 0.0:
			continue
		spawner.cooldown = spawner.interval

		# Forget spawns that are gone.
		var still_loose: Array[int] = []
		for child in spawner.spawned:
			if world.is_alive(child) and world.has(child, EcsPositionComponent):
				still_loose.append(child)
		spawner.spawned = still_loose

		# Pending requests count against the cap.
		if still_loose.size() + spawner.pending.size() >= spawner.max_loose:
			continue

		var here := world.get_component(id, EcsPositionComponent) as EcsPositionComponent
		var note := EcsSpawnRequest.new()
		note.type_id = spawner.spawns
		note.position = EcsConst.random_point_near(here.position, spawner.radius)
		inbox.spawn_requests.append(note)
		spawner.pending.append(note)

## Moves fulfilled requests onto `spawned`. Failed ones are dropped.
func _harvest(spawner: EcsSpawnerComponent) -> void:
	if spawner.pending.is_empty():
		return
	var waiting: Array[EcsSpawnRequest] = []
	for note in spawner.pending:
		if not note.fulfilled:
			waiting.append(note)
		elif note.born != EcsWorld.NO_ENTITY:
			spawner.spawned.append(note.born)
	spawner.pending = waiting
