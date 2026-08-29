class_name SimInventoryDef
extends SimComponentDef

## Blueprint for SimInventoryComponent. It carries no configuration — its mere
## presence is what lets the entity pick things up.

func slot() -> StringName:
	return &"inventory"

func build_into(entity: SimEntity) -> void:
	var component := SimInventoryComponent.new()
	component.name = "InventoryComponent"
	entity.add_child(component)
	entity.register_component(slot(), component)
