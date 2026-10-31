class_name EcsNeeds
extends RefCounted

## How pressing a need is, read the same way by the planner and the brain's ladder.

## Below its gate a need scores at least this fraction of its weight.
const FLOOR: float = 0.6

## 0 above `gate`, else from FLOOR at the gate to 1 at empty.
static func urgency(value: float, gate: float) -> float:
	if value > gate:
		return 0.0
	return FLOOR + (1.0 - FLOOR) * (gate - value) / maxf(gate, 0.01)

## How pressing food is, against the lower of hunger's two gates. 0 without hunger.
static func hunger_urgency(hunger: EcsHungerComponent) -> float:
	if hunger == null:
		return 0.0
	return urgency(hunger.fullness, minf(hunger.forage_below, hunger.eat_below))

## How pressing water is, against the lower of thirst's two gates. 0 without thirst.
static func thirst_urgency(thirst: EcsThirstComponent) -> float:
	if thirst == null:
		return 0.0
	return urgency(thirst.hydration, minf(thirst.seek_water_below, thirst.drink_below))

## At or below `parched_below`: won't sleep, wakes to drink.
static func parched(thirst: EcsThirstComponent) -> bool:
	return thirst != null and thirst.hydration <= thirst.parched_below
