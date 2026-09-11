class_name EcsDurabilitySystem
extends EcsSystem

## Wears the weapon down on every hit it dealt, and strips its damage when it
## breaks.
##
## This is the case that drove the rewrite. In the node-composition build a
## carried item had no live home for changing state, so durability meant either
## keeping a node parked in an inventory or hand-copying values in and out. Here
## the weapon is an entity id, its wear is a row in a table, and the system that
## owns that fact is the only thing that touches it. Nobody reaches into the
## weapon; nobody had to agree not to.

func label() -> StringName:
	return &"durability"

func run(world: EcsWorld, _delta: float) -> void:
	for event: EcsDamageEvent in world.events(EcsDamageEvent):
		var wear := world.get_component(event.weapon_id, EcsDurabilityComponent) as EcsDurabilityComponent
		if wear == null:
			continue
		wear.current = maxf(wear.current - wear.loss_per_hit, 0.0)
		if wear.current > 0.0:
			continue
		# Broken: the damage row goes away, so the attack system finds nothing on
		# the weapon next swing and falls back to unarmed on its own.
		world.remove(event.weapon_id, EcsDamageComponent)
		world.add(event.weapon_id, EcsBrokenComponent.new())
		var sprite := world.get_component(event.weapon_id, EcsSpriteComponent) as EcsSpriteComponent
		if sprite != null:
			sprite.tint = Color(0.45, 0.42, 0.40)
