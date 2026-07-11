class_name InventorySlot
extends Panel

## One inventory grid cell: shows an item's icon + stack count, or empty.

@onready var _icon: TextureRect = $Icon
@onready var _count: Label = $Count

## Renders the given stack (null / empty item clears the slot).
func set_stack(stack: ItemStack) -> void:
	if stack == null or stack.item == null:
		_icon.texture = null
		_count.text = ""
		return
	_icon.texture = stack.item.icon
	# Only surface a number for real stacks; single items stay uncluttered.
	_count.text = "x%d" % stack.count if stack.count > 1 else ""
