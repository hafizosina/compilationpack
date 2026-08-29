class_name SimFatigueComponent
extends SimBarComponent

## How rested the entity is: 100 is fresh, 0 is spent. Drains slowly while idle
## and faster while travelling, so movement has a cost.
##
## Fatigue asks Movement whether it is moving rather than Movement reporting to
## Fatigue — movement stays ignorant of needs, and an entity with no movement
## component simply never pays the travel cost.
##
## Collapse at zero (−20 HP, then sleep-locked until 50%) is step 6 and is NOT
## implemented; the bar currently just bottoms out.

## Extra units per second spent while the entity is travelling.
var move_drain_per_second: float = 1.5

func slot() -> StringName:
	return &"fatigue"

func bar_label() -> String:
	return "fatigue"

func extra_drain() -> float:
	var movement := entity.get_component(&"movement") as SimMovementComponent
	if movement != null and movement.is_moving():
		return move_drain_per_second
	return 0.0
