class_name SimEquipmentDef
extends SimComponentDef

## Blueprint for SimEquipmentComponent. DECLARED, NOT IMPLEMENTED — no
## blueprint carries it yet; it exists so the verb vocabulary lives in one place.

## Where it goes when equipped.
@export var body_slot: StringName = &"hand"

func slot() -> StringName:
	return &"equipment"

func stubs() -> Array[StringName]:
	return [&"equip"]

func build_into(entity: SimEntity) -> void:
	var component := SimEquipmentComponent.new()
	component.name = "EquipmentComponent"
	component.body_slot = body_slot
	entity.add_child(component)
	entity.register_component(slot(), component)
