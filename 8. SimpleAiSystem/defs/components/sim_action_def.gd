class_name SimActionDef
extends SimComponentDef

## Blueprint for SimActionComponent — the entity's reach. Keep it well under the
## sensor radius: the entity should have to travel to what it spots.

## Reach radius in pixels.
@export var radius: float = 56.0

func slot() -> StringName:
	return &"action"

func build_into(entity: SimEntity) -> void:
	var component := SimActionComponent.new()
	component.name = "ActionComponent"
	component.radius = radius
	entity.add_child(component)
	entity.register_component(slot(), component)
