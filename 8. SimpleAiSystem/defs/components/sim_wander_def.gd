class_name SimWanderDef
extends SimComponentDef

## Blueprint for SimWanderComponent. Requires a SimMovementDef earlier in the
## same blueprint's component list — wander drives movement, it does not replace it.

## Radius around the spawn point to wander within.
@export var radius: float = 256.0
## Seconds idled after arriving, before choosing the next destination.
@export var pause_min: float = 0.5
@export var pause_max: float = 2.0

func slot() -> StringName:
	return &"wander"

func build_into(entity: SimEntity) -> void:
	var component := SimWanderComponent.new()
	component.name = "WanderComponent"
	component.radius = radius
	component.pause_min = pause_min
	component.pause_max = pause_max
	entity.add_child(component)
	entity.register_component(slot(), component)
