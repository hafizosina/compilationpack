class_name SimInventoryComponent
extends SimComponent

## Somewhere to put what gets collected — and the owner of the pick-up action,
## since pick-up is the thing an inventory does.
##
## No inventory means the entity cannot pick anything up, and no action
## component means it cannot reach far enough to try. The dependency runs one
## way: inventory needs a hand, the hand knows nothing about inventories.

## Emitted whenever the contents change, carrying the new total.
signal changed(total: int)

## How many items fit. One slot means one berry at a time — collect it, and the
## entity has nowhere to put the next one until something empties this.
var capacity: int = 1

## item id -> count.
var _items: Dictionary = {}

func slot() -> StringName:
	return &"inventory"

## Attempts to pick `target` up. Returns false if this entity has no action
## component to reach with, if the target is out of reach, if it does not
## advertise pick-up, or if someone else claimed it first.
func try_pick_up(target: SimEntity) -> bool:
	if is_full():
		return false
	var action := entity.get_component(&"action") as SimActionComponent
	if action == null:
		return false
	if not action.in_reach(target):
		return false
	var pickable := target.get_component(&"pickupable") as SimPickUpAbleComponent
	if pickable == null:
		return false
	return pickable.take(entity, self)

## Whether there is no room left.
func is_full() -> bool:
	return total() >= capacity

## Stores `amount` of `item_id`. Returns false, changing nothing, when it will
## not fit — the caller must not consume anything it could not hand over.
func add(item_id: StringName, amount: int = 1) -> bool:
	if total() + amount > capacity:
		return false
	_items[item_id] = int(_items.get(item_id, 0)) + amount
	changed.emit(total())
	return true

func count_of(item_id: StringName) -> int:
	return int(_items.get(item_id, 0))

func total() -> int:
	var sum := 0
	for key in _items:
		sum += int(_items[key])
	return sum

func describe() -> Dictionary:
	var fields := {"slots": "%d / %d" % [total(), capacity]}
	if _items.is_empty():
		fields["carrying"] = "nothing"
		return fields
	for key in _items:
		fields[String(key)] = str(_items[key])
	return fields
