class_name SimFoodDef
extends SimComponentDef

## Blueprint for SimFoodComponent — what makes an entity edible.

## Hunger restored when eaten.
@export var hunger_value: float = 35.0

func slot() -> StringName:
	return &"food"

func build_into(entity: SimEntity) -> void:
	var component := SimFoodComponent.new()
	component.name = "FoodComponent"
	component.hunger_value = hunger_value
	entity.add_child(component)
	entity.register_component(slot(), component)
