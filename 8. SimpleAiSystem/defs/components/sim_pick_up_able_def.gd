class_name SimPickUpAbleDef
extends SimComponentDef

## Blueprint for SimPickUpAbleComponent — marks an entity as collectable.

func slot() -> StringName:
	return &"pickupable"

func build_into(entity: SimEntity) -> void:
	var component := SimPickUpAbleComponent.new()
	component.name = "PickUpAbleComponent"
	entity.add_child(component)
	entity.register_component(slot(), component)
