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

## item id -> count.
var _items: Dictionary = {}

func slot() -> StringName:
	return &"inventory"

## Attempts to pick `target` up. Returns false if this entity has no action
## component to reach with, if the target is out of reach, if it does not
## advertise pick-up, or if someone else claimed it first.
func try_pick_up(target: SimEntity) -> bool:
	var action := entity.get_component(&"action") as SimActionComponent
	if action == null:
		return false
	if not action.in_reach(target):
		return false
	var pickable := target.get_component(&"pickupable") as SimPickUpAbleComponent
	if pickable == null:
		return false
	return pickable.take(entity, self)

func add(item_id: StringName, amount: int = 1) -> void:
	_items[item_id] = int(_items.get(item_id, 0)) + amount
	changed.emit(total())

func count_of(item_id: StringName) -> int:
	return int(_items.get(item_id, 0))

func total() -> int:
	var sum := 0
	for key in _items:
		sum += int(_items[key])
	return sum

func describe() -> Dictionary:
	if _items.is_empty():
		return {"carrying": "nothing"}
	var fields := {}
	for key in _items:
		fields[String(key)] = str(_items[key])
	fields["total"] = str(total())
	return fields
