class_name EcsRotSystem
extends EcsSystem

## Ages everything that rots and flags it dying when its time is up.

func label() -> StringName:
	return &"rot"

func run(world: EcsWorld, delta: float) -> void:
	var rotting := world.view([EcsRotComponent], [EcsDyingFlag])
	var rots := rotting.column(EcsRotComponent)
	for k in rotting.ids.size():
		var rot := rots[k] as EcsRotComponent
		rot.age += delta
		if rot.age >= rot.lasts:
			var dying := EcsDyingFlag.new()
			dying.cause = EcsDyingFlag.ROTTED
			world.add(rotting.ids[k], dying)
