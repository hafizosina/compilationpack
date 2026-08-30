class_name SimConsumableDef
extends SimComponentDef

## Blueprint for SimConsumableComponent — what makes an entity edible, and how
## nourishing it is. The same number serves both paths: the live component uses
## it when something is eaten off the ground, and this def is what a carrier
## reads when eating from its own pocket.

## Hunger restored when consumed.
@export var nourishment: float = 35.0

func slot() -> StringName:
	return &"consumable"

func stubs() -> Array[StringName]:
	return [&"consume"]

func build_into(entity: SimEntity) -> void:
	var component := SimConsumableComponent.new()
	component.name = "ConsumableComponent"
	component.nourishment = nourishment
	entity.add_child(component)
	entity.register_component(slot(), component)
