class_name SimFatigueDef
extends SimBarDef

## Blueprint for SimFatigueComponent.

## Extra units per second spent while travelling.
@export var move_drain_per_second: float = 1.5

func slot() -> StringName:
	return &"fatigue"

func _make() -> SimBarComponent:
	return SimFatigueComponent.new()

func _configure(component: SimBarComponent) -> void:
	(component as SimFatigueComponent).move_drain_per_second = move_drain_per_second
