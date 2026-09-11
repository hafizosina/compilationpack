class_name EcsDeathSystem
extends EcsSystem

## Marks anything out of hit points as dead. It does not free the entity: the
## corpse keeps every component it had, which is what step 3 will turn into
## "harvestable" by adding a food component rather than by inventing a new kind
## of object.
##
## It darkens the sprite's tint rather than touching a node, because the render
## system is downstream and reads only data — appearance is a fact about the
## entity, not about the view.

func label() -> StringName:
	return &"death"

func run(world: EcsWorld, _delta: float) -> void:
	for id in world.query([EcsHealthComponent], [EcsDeadComponent]):
		var health := world.get_component(id, EcsHealthComponent) as EcsHealthComponent
		if health.hp > 0.0:
			continue
		world.add(id, EcsDeadComponent.new())
		world.remove(id, EcsAttackIntentComponent)
		var sprite := world.get_component(id, EcsSpriteComponent) as EcsSpriteComponent
		if sprite != null:
			sprite.tint = sprite.tint.darkened(0.55)
