class_name SimSensorDef
extends SimComponentDef

## Blueprint for SimSensorComponent. Without this def an entity perceives
## nothing and its brain has nothing to act on.

## Detection radius in pixels.
@export var radius: float = 360.0

func slot() -> StringName:
	return &"sensor"

func build_into(entity: SimEntity) -> void:
	var component := SimSensorComponent.new()
	component.name = "SensorComponent"
	component.radius = radius
	entity.add_child(component)
	entity.register_component(slot(), component)
