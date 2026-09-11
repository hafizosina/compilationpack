class_name EcsWeaponCarrySystem
extends EcsSystem

## Parks each wielded weapon on its wielder. The weapon keeps its own
## EcsPositionComponent — it is a full entity, not a passenger — so "carried"
## is one system writing one field, and dropping the weapon later means nothing
## more than clearing the link.

func label() -> StringName:
	return &"weapon_carry"

func run(world: EcsWorld, _delta: float) -> void:
	for id in world.query([EcsEquippedComponent, EcsPositionComponent]):
		var equipped := world.get_component(id, EcsEquippedComponent) as EcsEquippedComponent
		var carried := world.get_component(equipped.weapon_id, EcsPositionComponent) as EcsPositionComponent
		if carried == null:
			continue
		var holder := world.get_component(id, EcsPositionComponent) as EcsPositionComponent
		carried.position = holder.position + equipped.offset
