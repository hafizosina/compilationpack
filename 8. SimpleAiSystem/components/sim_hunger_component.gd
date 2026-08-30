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
## Drain multiplier while the entity is asleep — a sleeping animal still gets
## hungry, just slower. Read from the entity's own `is_sleeping` flag, so this
## never touches FatigueComponent and the two bars stay independent.
var sleep_drain_scale: float = 0.25

## Whether Health may regenerate. Health asks this rather than reading the
## number, so the threshold lives with the bar that owns it.
func is_well_fed() -> bool:
	return value > well_fed_above

## Whether the entity should be looking for food. The brain asks this; the
## number behind it stays here.
func is_hungry() -> bool:
	return value <= well_fed_above

func drain_scale() -> float:
	return sleep_drain_scale if entity != null and entity.is_sleeping else 1.0

## Consumes `target`, whatever it is and wherever it came from.
##
## It accepts either a live entity in the world or a blueprint snapshot out of
## someone's pocket, and in both cases asks the same question — does this offer
## the `consume` stub? — rather than checking what it is.
##
## Hunger never touches Inventory. A live target resolves itself and disappears;
## a snapshot cannot, so this announces `thing_used` on the entity and whoever
## is holding it drops it. That announcement is the only coupling, and it points
## at nobody in particular.
func eat(target) -> bool:
	if target is SimEntity:
		var consumable := target.find_with_stub(&"consume") as SimConsumableComponent
		if consumable == null or not consumable.is_available():
			return false
		# The live component resolves it: restores this bar and frees itself.
		return consumable.consume(entity, self)

	if target is SimEntityDef:
		var def := target.find_with_stub(&"consume") as SimConsumableDef
		if def == null:
			return false
		restore(def.nourishment)
		entity.thing_used.emit(&"consume", target)
		return true

	return false

func _process(delta: float) -> void:
	super(delta)
	if not is_empty() or starve_damage_per_second <= 0.0:
		return
	var health := entity.get_component(&"health") as SimHealthComponent
	if health != null:
		health.spend(starve_damage_per_second * delta)
