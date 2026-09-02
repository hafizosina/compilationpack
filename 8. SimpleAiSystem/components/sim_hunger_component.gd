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

func slot() -> StringName:
	return &"hunger"

func bar_label() -> String:
	return "hunger"

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

## Consumes `snapshot` — a blueprint of something edible.
##
## There is ONE eating path because there is only one kind of argument. Whoever
## calls this has already resolved the thing into a snapshot: a pocket holds one
## outright, and something on the ground is won through
## SimEntity.claim_snapshot() first. That decision belongs to the caller, which
## already knows which of the two it is looking at, so nothing here has to ask
## what it was handed.
##
## Nothing here knows what a berry is either. It asks whether the thing offers
## the `consume` stub — the same question the sensor and the inventory ask — and
## reads the amount from that def, so ground-eating and pocket-eating cannot
## drift apart.
##
## Hunger never touches Inventory. It announces `thing_used` on its own entity;
## if an inventory happened to hold the thing, that inventory drops it.
func eat(snapshot: SimEntityDef) -> bool:
	if snapshot == null:
		return false
	var def := snapshot.find_with_stub(&"consume") as SimConsumableDef
	if def == null:
		return false
	restore(def.nourishment)
	entity.thing_used.emit(&"consume", snapshot)
	return true

func _process(delta: float) -> void:
	super(delta)
	if not is_empty() or starve_damage_per_second <= 0.0:
		return
	var health := entity.get_component(&"health") as SimHealthComponent
	if health != null:
		health.spend(starve_damage_per_second * delta)
