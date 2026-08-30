class_name SimPlaceAbleDef
extends SimComponentDef

## Blueprint for SimPlaceAbleComponent. DECLARED, NOT IMPLEMENTED — no
## blueprint carries it yet; it exists so the verb vocabulary lives in one place.

func slot() -> StringName:
	return &"placeable"

func stubs() -> Array[StringName]:
	return [&"place_item"]

func build_into(entity: SimEntity) -> void:
	var component := SimPlaceAbleComponent.new()
	component.name = "PlaceAbleComponent"
	entity.add_child(component)
	entity.register_component(slot(), component)
