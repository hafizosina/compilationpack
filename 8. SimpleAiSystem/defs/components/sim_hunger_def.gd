class_name SimHungerDef
extends SimBarDef

## Blueprint for SimHungerComponent.

## Above this the entity is well fed; at or below it, it should seek food.
@export var well_fed_above: float = 50.0
## Health lost per second while hunger is empty.
@export var starve_damage_per_second: float = 2.0
## Drain multiplier while the entity is asleep.
@export var sleep_drain_scale: float = 0.25
## Eats whenever hunger is below this. 100 = eat as soon as it carries food.
@export var eat_below: float = 100.0

func slot() -> StringName:
	return &"hunger"

func _make() -> SimBarComponent:
	return SimHungerComponent.new()

func _configure(component: SimBarComponent) -> void:
	var hunger := component as SimHungerComponent
	hunger.well_fed_above = well_fed_above
	hunger.starve_damage_per_second = starve_damage_per_second
	hunger.sleep_drain_scale = sleep_drain_scale
	hunger.eat_below = eat_below
