class_name EcsHealthSystem
extends EcsSystem

## Flags an entity dying when its health reaches zero.

func label() -> StringName:
	return &"health"

func run(world: EcsWorld, _delta: float) -> void:
	var living := world.view([EcsHealthComponent], [EcsDyingFlag])
	var healths := living.column(EcsHealthComponent)
	for k in living.ids.size():
		if (healths[k] as EcsHealthComponent).value > 0.0:
			continue
		world.add(living.ids[k], EcsDyingFlag.new())
