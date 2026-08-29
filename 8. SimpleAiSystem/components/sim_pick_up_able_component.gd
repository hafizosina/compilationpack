class_name SimPickUpAbleComponent
extends SimComponent

## Target-side affordance: this entity can be picked up.
##
## Actor declares, target resolves — the actor's InventoryComponent asks, and
## this component owns what actually happens: the item lands in that inventory
## and the world entity removes itself.

## What lands in the picker's inventory.
var item_id: StringName = &"item"

## Emitted just before the entity removes itself.
signal picked_up(actor: SimEntity)

var _taken: bool = false

func slot() -> StringName:
	return &"pickupable"

## False once someone has claimed this, even if the node has not been freed yet.
func is_available() -> bool:
	return not _taken

## Resolves a pick-up by `actor`. The guard matters: several animals can be
## converging on the same berry, and only the first may have it.
func take(actor: SimEntity, inventory: SimInventoryComponent) -> bool:
	if _taken:
		return false
	# Only vanish if the item was actually stored — a full inventory must leave
	# the berry in the world for someone else.
	if not inventory.add(item_id):
		return false
	_taken = true
	picked_up.emit(actor)
	# Detached immediately, not just queue_free()d: a queued node stays in the
	# tree until the end of the frame, so other sensors would keep detecting a
	# berry that is already gone.
	var parent := entity.get_parent()
	if parent != null:
		parent.remove_child(entity)
	entity.queue_free()
	return true

func describe() -> Dictionary:
	return {
		"item": String(item_id),
		"state": "available" if is_available() else "taken",
	}
