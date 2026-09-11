class_name EcsAttackSystem
extends EcsSystem

## Turns an intent into a damage event. This is the attacker's whole side of a
## hit: who swung, with what, for how much. It reads nothing off the defender —
## not armour, not resistances, not whether the blow will kill — so armour was
## added to this simulation without this file being opened.
##
## Weapon or fist is not a branch on a type. The wielded entity is asked for an
## EcsDamageComponent; if it has none (never had one, or the durability system
## stripped it when it broke) the attacker's own damage answers instead.

func label() -> StringName:
	return &"attack"

func run(world: EcsWorld, _delta: float) -> void:
	for id in world.query([EcsAttackIntentComponent], [EcsDeadComponent]):
		var intent := world.get_component(id, EcsAttackIntentComponent) as EcsAttackIntentComponent
		# Consumed whether or not it lands — an intent lasts exactly one frame.
		world.remove(id, EcsAttackIntentComponent)

		var target := intent.target_id
		if not world.is_alive(target) or world.has(target, EcsDeadComponent):
			continue

		var weapon_id := EcsWorld.NO_ENTITY
		var equipped := world.get_component(id, EcsEquippedComponent) as EcsEquippedComponent
		if equipped != null:
			weapon_id = equipped.weapon_id

		var damage := world.get_component(weapon_id, EcsDamageComponent) as EcsDamageComponent
		if damage == null:
			weapon_id = EcsWorld.NO_ENTITY
			damage = world.get_component(id, EcsDamageComponent) as EcsDamageComponent
		if damage == null:
			continue

		world.emit_event(EcsDamageEvent.new(id, target, weapon_id, damage.amount))
