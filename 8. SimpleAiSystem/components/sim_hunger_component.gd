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
## Eats whenever hunger sits below this. 100 means "eat as soon as you carry
## food and are not completely full" — the placeholder for a real decision.
## Lower it (to `well_fed_above`, say) to make animals carry food until hungry.
var eat_below: float = 100.0

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

## Whether the entity should be looking for food.
func is_hungry() -> bool:
	return value <= well_fed_above

func drain_scale() -> float:
	return sleep_drain_scale if entity != null and entity.is_sleeping else 1.0

## Eats one carried thing. Hunger owns eating for the same reason Inventory owns
## pick-up: it is the component with the appetite, as Inventory is the one with
## the pocket.
##
## Nothing here knows what a berry is. It asks the inventory for a held entity
## carrying a `food` component — the same "find by capability" question the
## sensor asks of the world — and that component decides what eating does.
##
## Called from _process for now: with no planner, "eat what you are carrying" is
## not much of a decision. GOAP takes it over as a real action in step 5, at
## which point this self-trigger goes and the brain calls try_eat() instead.
func try_eat() -> bool:
	var inventory := entity.get_component(&"inventory") as SimInventoryComponent
	if inventory == null:
		return false
	var carried := inventory.held_with(&"food")
	if carried == null:
		return false
	var food := carried.get_component(&"food") as SimFoodComponent
	if food == null or not food.is_available():
		return false
	if not food.consume(entity, self):
		return false
	inventory.release(carried)
	return true

func _process(delta: float) -> void:
	super(delta)
	# A sleeping animal does not rummage in its own pockets.
	if value < eat_below and not entity.is_sleeping:
		try_eat()
	if not is_empty() or starve_damage_per_second <= 0.0:
		return
	var health := entity.get_component(&"health") as SimHealthComponent
	if health != null:
		health.spend(starve_damage_per_second * delta)
