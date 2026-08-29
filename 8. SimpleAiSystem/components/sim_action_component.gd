class_name SimActionComponent
extends SimSensorComponent

## The performer: a short-range Area2D plus the handshake that runs an action on
## a target. Reuses the sensor's area building and overlap queries — reach is
## just a much smaller detection radius.
##
## Pairing rule: an action fires only if the TARGET advertises it (has the
## affordance component) AND the ACTOR has the paired component. Pick-up needs
## the target's PickUpAble and the actor's Inventory. No type checks anywhere.

func slot() -> StringName:
	return &"action"

## Whether `target` is close enough to act on.
func in_reach(target: SimEntity) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	return get_detected().has(target)

## Attempts to pick `target` up. Returns false if out of reach, if the target
## does not advertise pick-up, or if this entity has no inventory to put it in.
func try_pick_up(target: SimEntity) -> bool:
	if not in_reach(target):
		return false
	var inventory := entity.get_component(&"inventory") as SimInventoryComponent
	if inventory == null:
		return false
	var pickable := target.get_component(&"pickupable") as SimPickUpAbleComponent
	if pickable == null:
		return false
	return pickable.take(entity, inventory)

func describe() -> Dictionary:
	return {
		"reach": "%.0f px" % radius,
		"in reach": "%d" % get_detected().size(),
	}
