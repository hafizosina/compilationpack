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

## How strongly flockmates pull a wander destination. 0 disables flocking
## entirely; only entities of the SAME blueprint ever count as flockmates.
@export_range(0.0, 1.0) var flock_weight: float = 0.55
## Neighbours closer than this push back, keeping the flock from collapsing.
@export var flock_separation: float = 110.0

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
	component.flock_weight = flock_weight
	component.flock_separation = flock_separation
	entity.add_child(component)
	entity.register_component(slot(), component)
