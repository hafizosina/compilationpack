class_name SimInventoryComponent
extends SimComponent

## Actor-side pairing for pick-up: somewhere to put what gets collected.
## No component here means the entity simply cannot pick anything up.

## Emitted whenever the contents change, carrying the new total.
signal changed(total: int)

## item id -> count.
var _items: Dictionary = {}

func slot() -> StringName:
	return &"inventory"

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
