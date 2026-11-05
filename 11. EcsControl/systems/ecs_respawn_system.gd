class_name EcsRespawnSystem
extends EcsSystem

## Counts down each EcsRespawnComponent; when it is due, asks lifecycle for its blueprint
## where it stands and marks itself dying.

func label() -> StringName:
	return &"respawn"

func run(world: EcsWorld, delta: float) -> void:
	var inbox := world.get_singleton(EcsLifecycleSingleton) as EcsLifecycleSingleton
	if inbox == null:
		return
	for id in world.query([EcsRespawnComponent, EcsPositionComponent], [EcsDyingFlag]):
		var respawn := world.get_component(id, EcsRespawnComponent) as EcsRespawnComponent
		respawn.waited += delta
		if respawn.waited < respawn.after:
			continue
		var note := EcsSpawnRequest.new()
		note.type_id = respawn.blueprint
		note.position = (world.get_component(id, EcsPositionComponent) as EcsPositionComponent).position
		inbox.spawn_requests.append(note)
		var dying := EcsDyingFlag.new()
		dying.cause = EcsDyingFlag.REMOVED
		world.add(id, dying)
