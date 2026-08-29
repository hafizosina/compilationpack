class_name SimHealthDef
extends SimBarDef

## Blueprint for SimHealthComponent. No Health def means the entity cannot be
## hurt at all.

## Health regained per second while Hunger is above its well-fed threshold.
@export var regen_per_second: float = 1.0

func slot() -> StringName:
	return &"health"

func _make() -> SimBarComponent:
	return SimHealthComponent.new()

func _configure(component: SimBarComponent) -> void:
	(component as SimHealthComponent).regen_per_second = regen_per_second
