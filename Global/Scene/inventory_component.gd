class_name InventoryComponent
extends EntityComponent

## Gives its parent Entity an inventory. Attach as a child of an Entity; the
## EntityComponent base resolves `entity` from the parent. Contents change only
## through this API (add_item / remove_item) — the UI just displays them.

## Number of slots this inventory holds.
@export var capacity: int = 20
## Items granted on ready. Repeat an entry to seed a stack (e.g. coin ×3).
@export var starting_items: Array[Item] = []

## Fixed-size list of stacks; a null entry means an empty slot.
var slots: Array[ItemStack] = []

func _ready() -> void:
	super()  # binds `entity` from the parent Entity
	slots.resize(capacity)
	for item in starting_items:
		add_item(item)
	# Deferred so the inventory UI (which connects in its own _ready) reliably
	# receives this initial state regardless of node _ready order.
	_emit_changed.call_deferred()

## Adds count of item, topping up existing stacks first then filling empty slots.
## Returns the amount that did not fit (0 when everything was stored).
func add_item(item: Item, count: int = 1) -> int:
	if item == null or count <= 0:
		return count
	var remaining := count
	# Top up existing stacks of the same item.
	for stack in slots:
		if remaining <= 0:
			break
		if stack != null and stack.item == item:
			var moved := mini(item.max_stack - stack.count, remaining)
			stack.count += moved
			remaining -= moved
	# Spill the rest into empty slots as new stacks.
	for i in slots.size():
		if remaining <= 0:
			break
		if slots[i] == null:
			var stack := ItemStack.new()
			stack.item = item
			stack.count = mini(item.max_stack, remaining)
			remaining -= stack.count
			slots[i] = stack
	if remaining != count:
		_emit_changed()
	return remaining

## Removes count of item across stacks. Returns the amount actually removed.
func remove_item(item: Item, count: int = 1) -> int:
	if item == null or count <= 0:
		return 0
	var remaining := count
	for i in slots.size():
		if remaining <= 0:
			break
		var stack := slots[i]
		if stack != null and stack.item == item:
			var taken := mini(stack.count, remaining)
			stack.count -= taken
			remaining -= taken
			if stack.count <= 0:
				slots[i] = null
	var removed := count - remaining
	if removed > 0:
		_emit_changed()
	return removed

## Total count of an item across all stacks.
func count_of(item: Item) -> int:
	var total := 0
	for stack in slots:
		if stack != null and stack.item == item:
			total += stack.count
	return total

func has_item(item: Item) -> bool:
	return count_of(item) > 0

func _emit_changed() -> void:
	EventBus.inventory_changed.emit(slots)
