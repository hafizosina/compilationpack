class_name SimInventoryDef
extends SimComponentDef

## Blueprint for SimInventoryComponent. Its presence is what lets the entity
## pick things up at all; `capacity` decides how much it can hold before it has
## to stop.

## How many items fit.
@export var capacity: int = 1

func slot() -> StringName:
	return &"inventory"

func build_into(entity: SimEntity) -> void:
	var component := SimInventoryComponent.new()
	component.name = "InventoryComponent"
	component.capacity = capacity
	entity.add_child(component)
	entity.register_component(slot(), component)
