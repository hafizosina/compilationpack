class_name EcsHealthSystem
extends EcsSystem

## Owns what happens when health runs out, and nothing else.
##
## It does not heal — there is one damage source in the module (starvation) and
## regeneration would only undo it. It does not deal damage either; whatever
## spends health does that where its own rule lives. All this owns is the
## threshold, which is exactly one comparison and the module's only death by
## simulation.
##
## Killing is a **flag**, not an act. EcsEntityManager is the only thing that
## destroys an entity, its data or its nodes, and it does so at the lifecycle
## stage at the top of the next tick — so a creature that dies here is still
## walking around for the rest of this frame and every system after this one
## sees the same world it started with.

func label() -> StringName:
	return &"health"

func run(world: EcsWorld, _delta: float) -> void:
	# Naming EcsDyingFlag costs little: it is raised only on the way to a death,
	# and a death rebuilds this view anyway — the one extra is a berry taken,
	# which dies without touching the health table.
	var living := world.view([EcsHealthComponent], [EcsDyingFlag])
	var healths := living.column(EcsHealthComponent)
	for k in living.ids.size():
		if (healths[k] as EcsHealthComponent).value > 0.0:
			continue
		world.add(living.ids[k], EcsDyingFlag.new())
