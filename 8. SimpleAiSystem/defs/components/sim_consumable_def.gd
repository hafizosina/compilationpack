class_name SimConsumableDef
extends SimComponentDef

## Blueprint for SimConsumableComponent — what makes an entity edible, and how
## nourishing it is. This def is the ONLY place the number lives: eating reads
## it from here whether the thing came off the ground or out of a pocket, so the
## two cannot drift apart.

## Hunger restored when consumed.
@export var nourishment: float = 35.0

func slot() -> StringName:
	return &"consumable"

func stubs() -> Array[StringName]:
	return [&"consume"]

func build_into(entity: SimEntity) -> void:
	var component := SimConsumableComponent.new()
	component.name = "ConsumableComponent"
	entity.add_child(component)
	entity.register_component(slot(), component)
