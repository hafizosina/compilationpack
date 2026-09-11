class_name EcsDamageSystem
extends EcsSystem

## The defender's whole side of a hit: take the incoming amount, blunt it by
## whatever armour this entity happens to carry, spend it on health.
##
## It never asks who swung or with what. That is the point — an event carries
## the attacker's answer, this system supplies the defender's, and neither had
## to be taught about the other.

func label() -> StringName:
	return &"damage"

func run(world: EcsWorld, _delta: float) -> void:
	for event: EcsDamageEvent in world.events(EcsDamageEvent):
		var health := world.get_component(event.to, EcsHealthComponent) as EcsHealthComponent
		if health == null:
			continue
		var taken := event.amount
		var armor := world.get_component(event.to, EcsArmorComponent) as EcsArmorComponent
		if armor != null:
			taken = maxf(taken - armor.reduction, armor.minimum)
		health.hp = maxf(health.hp - taken, 0.0)
