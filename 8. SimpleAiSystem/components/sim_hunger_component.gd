class_name SimHungerComponent
extends SimBarComponent

## Fullness, not emptiness: 100 is sated, 0 is starving.
##
## The 50 line is the pivot from COLONY_SIM_CONCEPT.md §2 — above it Health
## regenerates, below it the food goal activates. At zero it damages Health, so
## a creature that cannot feed itself eventually dies of it.

## Above this, the entity counts as well fed and Health regenerates.
var well_fed_above: float = 50.0
## Health lost per second while completely empty.
var starve_damage_per_second: float = 2.0

func slot() -> StringName:
	return &"hunger"

func bar_label() -> String:
	return "hunger"

## Whether Health may regenerate. Health asks this rather than reading the
## number, so the threshold lives with the bar that owns it.
func is_well_fed() -> bool:
	return value > well_fed_above

## Whether the entity should be looking for food.
func is_hungry() -> bool:
	return value <= well_fed_above

func _process(delta: float) -> void:
	super(delta)
	if not is_empty() or starve_damage_per_second <= 0.0:
		return
	var health := entity.get_component(&"health") as SimHealthComponent
	if health != null:
		health.spend(starve_damage_per_second * delta)
