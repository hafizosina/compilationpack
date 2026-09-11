class_name EcsAggressionComponent
extends EcsComponent

## Placeholder brain config: attack the nearest attackable thing in reach, on a
## timer. Step 6 replaces the system that reads this with an FSM and then a
## planner — and nothing downstream changes, because all any of them do is
## write an EcsAttackIntentComponent.

## How far it will strike.
@export var reach: float = 260.0
## Seconds between swings.
@export var interval: float = 1.2

## Seconds until the next swing. Runtime state.
var cooldown: float = 0.0

func key() -> StringName:
	return &"aggression"
