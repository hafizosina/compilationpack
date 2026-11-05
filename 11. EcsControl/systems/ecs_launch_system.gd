class_name EcsLaunchSystem
extends EcsSystem

## Executes EcsLaunchFlag once: asks lifecycle for its projectile just ahead of the caster,
## flying along the facing with the caster's damage times the scale, and starts a short thrust.

## How far ahead of the caster's centre the projectile appears.
const AHEAD: float = 30.0

func label() -> StringName:
	return &"launch"

func run(world: EcsWorld, _delta: float) -> void:
	var inbox := world.get_singleton(EcsLifecycleSingleton) as EcsLifecycleSingleton
	if inbox == null:
		return
	for id in world.query([EcsLaunchFlag, EcsPositionComponent], [EcsDyingFlag]):
		var launch := world.get_component(id, EcsLaunchFlag) as EcsLaunchFlag
		if launch.launched:
			continue
		launch.launched = true
		var player := world.get_component(id, EcsPlayerComponent) as EcsPlayerComponent
		var facing := player.facing if player != null else Vector2.RIGHT
		var attack := world.get_component(id, EcsDamageComponent) as EcsDamageComponent
		var note := EcsSpawnRequest.new()
		note.type_id = launch.blueprint
		note.position = (world.get_component(id, EcsPositionComponent) as EcsPositionComponent).position + facing * AHEAD
		note.overrides = {"projectile": {
			"direction": facing,
			"owner": id,
			"damage": (attack.damage if attack != null else 10.0) * launch.damage_scale,
		}}
		inbox.spawn_requests.append(note)
		if world.has(id, EcsWeaponComponent) and not world.has(id, EcsSwingFlag):
			var thrust := EcsSwingFlag.new()
			thrust.direction = facing.angle()
			thrust.arc = 40.0
			thrust.duration = 0.15
			world.add(id, thrust)
