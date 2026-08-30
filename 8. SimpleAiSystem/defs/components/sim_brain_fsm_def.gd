class_name SimBrainFSMDef
extends SimBrainDef

## Blueprint for SimBrainFSMComponent — the state-machine brain, which owns both
## seeking and wandering. Requires sensor and movement defs; action and inventory
## defs are what let it actually pick anything up.

## Seconds between decisions.
@export var think_interval: float = 0.25
## Which affordance the brain seeks out.
@export var wanted: StringName = &"pickupable"
## Behaviour modifiers. Leave empty for plain default behaviour; add a
## SimFlockTrait to make this type herd, and so on. This is how two blueprints
## sharing the one brain end up behaving differently.
@export var traits: Array[SimTrait] = []
## How far one wander step may travel from where the entity stands.
@export var wander_radius: float = 420.0
## Seconds idled after arriving, before choosing the next wander destination.
@export var wander_pause_min: float = 0.3
@export var wander_pause_max: float = 1.2


func _make() -> SimBrainComponent:
	return SimBrainFSMComponent.new()

func _configure(brain: SimBrainComponent) -> void:
	var component := brain as SimBrainFSMComponent
	component.think_interval = think_interval
	component.wanted = wanted
	component.wander_radius = wander_radius
	component.wander_pause_min = wander_pause_min
	component.wander_pause_max = wander_pause_max
	component.traits = traits
