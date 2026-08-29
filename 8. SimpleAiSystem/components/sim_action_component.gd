class_name SimActionComponent
extends SimSensorComponent

## The hand: a short-range Area2D that answers one question — is that target
## close enough to act on? Reuses the sensor's area building and overlap
## queries, because reach is just a much smaller detection radius.
##
## It knows nothing about any particular action. Picking up lives on
## InventoryComponent, attacking would live on AttackComponent; both ask this
## component whether they can reach, and neither is referenced from here. An
## entity with a hand but no pockets simply cannot pick anything up, and no code
## here has to care.

func slot() -> StringName:
	return &"action"

## Whether `target` is close enough to act on.
func in_reach(target: SimEntity) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	return get_detected().has(target)
