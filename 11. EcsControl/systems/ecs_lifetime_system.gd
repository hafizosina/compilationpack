class_name EcsLifetimeSystem
extends EcsSystem

## Ages everything with EcsLifetimeComponent and marks it dying when its time is up.

func label() -> StringName:
	return &"lifetime"

func run(world: EcsWorld, delta: float) -> void:
	for id in world.query([EcsLifetimeComponent], [EcsDyingFlag]):
		var life := world.get_component(id, EcsLifetimeComponent) as EcsLifetimeComponent
		life.age += delta
		if life.age >= life.seconds:
			var dying := EcsDyingFlag.new()
			dying.cause = EcsDyingFlag.REMOVED
			dying.detail = &"expired"
			world.add(id, dying)
