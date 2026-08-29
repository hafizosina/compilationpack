class_name SimPickUpAbleDef
extends SimComponentDef

## Blueprint for SimPickUpAbleComponent — marks an entity as collectable.

## What lands in the picker's inventory.
@export var item_id: StringName = &"berry"

func slot() -> StringName:
	return &"pickupable"

func build_into(entity: SimEntity) -> void:
	var component := SimPickUpAbleComponent.new()
	component.name = "PickUpAbleComponent"
	component.item_id = item_id
	entity.add_child(component)
	entity.register_component(slot(), component)
