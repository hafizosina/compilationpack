class_name SimFatigueDef
extends SimBarDef

## Blueprint for SimFatigueComponent.

## Extra units per second spent while travelling.
@export var move_drain_per_second: float = 1.5
## Energy the entity must recover after collapsing before it wakes.
@export var wake_at: float = 50.0
## Energy regained per second while asleep.
@export var recover_per_second: float = 1.0

func slot() -> StringName:
	return &"fatigue"

func _make() -> SimBarComponent:
	return SimFatigueComponent.new()

func _configure(component: SimBarComponent) -> void:
	var fatigue := component as SimFatigueComponent
	fatigue.move_drain_per_second = move_drain_per_second
	fatigue.wake_at = wake_at
	fatigue.recover_per_second = recover_per_second
