class_name EcsEquipSystem
extends EcsSystem

## Turns authored weapon *names* into weapon *ids*, once each. A .tres has no
## way to write a runtime id, so the blueprint says "I wield dagger_0" and this
## system resolves that against the name table after everything has spawned.
##
## It also drops the link when the weapon stops existing, so nothing downstream
## has to defend against a dangling id.

func label() -> StringName:
	return &"equip"

func run(world: EcsWorld, _delta: float) -> void:
	var names: Dictionary = {}
	for id in world.query([EcsEquippedComponent]):
		var equipped := world.get_component(id, EcsEquippedComponent) as EcsEquippedComponent
		if world.is_alive(equipped.weapon_id):
			continue
		equipped.weapon_id = EcsWorld.NO_ENTITY
		if equipped.weapon_name == &"":
			continue
		# Built lazily: in the steady state every link is already resolved and
		# this system costs one empty query.
		if names.is_empty():
			names = _name_index(world)
		equipped.weapon_id = names.get(equipped.weapon_name, EcsWorld.NO_ENTITY)
		if equipped.weapon_id == EcsWorld.NO_ENTITY:
			push_warning("EcsEquipSystem: entity %d wields unknown '%s'"
				% [id, equipped.weapon_name])
			equipped.weapon_name = &""

func _name_index(world: EcsWorld) -> Dictionary:
	var index: Dictionary = {}
	for id in world.query([EcsNameComponent]):
		var named := world.get_component(id, EcsNameComponent) as EcsNameComponent
		index[named.entity_name] = id
	return index
