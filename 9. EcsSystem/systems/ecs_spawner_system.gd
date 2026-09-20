class_name EcsSpawnerSystem
extends EcsSystem

## Runs every spawner's clock and asks for another entity when it is due.
##
## It used to create entities itself, holding the factory and calling it
## mid-query. It now writes a note to EcsLifecycleComponent and EcsEntityManager
## fulfils it at the top of the next tick, which is the whole point of the
## lifecycle stage: no system changes the shape of the world while another
## system is walking it.
##
## The cost is one tick between asking and appearing, and it is genuinely one
## tick — the berry is built at the very start of the next frame, so every
## system that follows sees it and draws it in that same frame. There is still
## no moment where an entity exists without a node, which was the property the
## old "spawn first, in the same tick" ordering was really protecting.
##
## In exchange the spawner no longer needs the factory or the catalog: it names
## a blueprint and something else knows what that means.

func label() -> StringName:
	return &"spawner"

func run(world: EcsWorld, delta: float) -> void:
	var inbox := world.get_singleton(EcsLifecycleComponent) as EcsLifecycleComponent
	if inbox == null:
		return

	for id in world.query([EcsPositionComponent, EcsSpawnerComponent]):
		var spawner := world.get_component(id, EcsSpawnerComponent) as EcsSpawnerComponent
		_harvest(spawner)

		spawner.cooldown -= delta
		if spawner.cooldown > 0.0:
			continue
		spawner.cooldown = spawner.interval

		# Prune first, so anything harvested since last tick frees its slot.
		# Still on the ground means alive AND still carrying a position.
		var still_loose: Array[int] = []
		for child in spawner.spawned:
			if world.is_alive(child) and world.has(child, EcsPositionComponent):
				still_loose.append(child)
		spawner.spawned = still_loose

		# Notes already in flight count against the cap. Without that the
		# spawner would re-ask every tick until the first one landed and blow
		# straight past max_loose.
		if still_loose.size() + spawner.pending.size() >= spawner.max_loose:
			continue

		var here := world.get_component(id, EcsPositionComponent) as EcsPositionComponent
		var note := EcsSpawnRequest.new()
		note.type_id = spawner.spawns
		note.position = EcsConst.random_point_near(here.position, spawner.radius)
		inbox.spawn_requests.append(note)
		spawner.pending.append(note)

## Moves fulfilled notes onto the spawned list and drops them. A note the
## manager could not fulfil — an unknown blueprint — is dropped too, rather
## than held against the cap forever.
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
