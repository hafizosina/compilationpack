class_name EcsBreedingComponent
extends EcsComponent

## How it breeds: with a ready partner of its kind, when well fed and watered and off
## cooldown. EcsBreedingSystem decides readiness and carries out a mating.

## Share of max fullness and hydration both must be at or above to be ready.
@export_range(0.0, 1.0) var ready_above: float = 0.75
## Seconds between births, for each parent.
@export var cooldown: float = 240.0
## Fullness and hydration each parent pays for a birth.
@export var cost: float = 40.0
## Newborns per birth.
@export var litter: int = 1

## Seconds until it may breed again.
var cooldown_left: float = 0.0
## Whether the start cooldown has been rolled. A placement that sets `cooldown_left`
## sets this beside it.
var rolled: bool = false

func key() -> StringName:
	return &"breeding"

func describe() -> Dictionary:
	return {"tab": &"entity", "lines": {"breeds in": "%ds" % ceili(cooldown_left) if cooldown_left > 0.0 else "ready"}}
