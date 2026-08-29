class_name SimBrainDef
extends SimComponentDef

## Blueprint for SimBrainComponent — the simple AI, which owns both seeking and
## wandering. Requires sensor and movement defs; action and inventory defs are
## what let it actually pick anything up.

## Seconds between decisions.
@export var think_interval: float = 0.25
## Which affordance the brain seeks out.
@export var wanted: StringName = &"pickupable"
## How far one wander step may travel from where the entity stands.
@export var wander_radius: float = 420.0
## Seconds idled after arriving, before choosing the next wander destination.
@export var wander_pause_min: float = 0.3
@export var wander_pause_max: float = 1.2

func slot() -> StringName:
	return &"brain"

func build_into(entity: SimEntity) -> void:
	var component := SimBrainComponent.new()
	component.name = "BrainComponent"
	component.think_interval = think_interval
	component.wanted = wanted
	component.wander_radius = wander_radius
	component.wander_pause_min = wander_pause_min
	component.wander_pause_max = wander_pause_max
	entity.add_child(component)
	entity.register_component(slot(), component)
