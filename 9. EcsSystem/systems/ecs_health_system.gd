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
## Killing is a **note**, not an act. EcsEntityManager is the only thing that
## destroys an entity, its data or its nodes, and it does so at the lifecycle
## stage at the top of the next tick — so a creature that dies here is still
## walking around for the rest of this frame and every system after this one
## sees the same world it started with.

func label() -> StringName:
	return &"health"

func run(world: EcsWorld, _delta: float) -> void:
	var lifecycle := world.get_singleton(EcsLifecycleSingleton) as EcsLifecycleSingleton
	if lifecycle == null:
		return
	for id in world.query([EcsHealthComponent]):
		var health := world.get_component(id, EcsHealthComponent) as EcsHealthComponent
		if health.value > 0.0:
			continue
		if not lifecycle.kill_requests.has(id):
			lifecycle.kill_requests.append(id)
