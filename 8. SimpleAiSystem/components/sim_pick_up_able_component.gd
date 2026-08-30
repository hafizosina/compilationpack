class_name SimPickUpAbleComponent
extends SimComponent

## Target-side affordance: this entity can be picked up.
##
## Being carried does not destroy the entity — it is **moved into the carrier's
## inventory**, keeping its components alive. That is what lets a berry still be
##食 food after it has been pocketed: nothing had to copy its hunger value out
## into item data, because the entity that owns the FoodComponent still exists.

## Emitted just before the entity leaves the world.
signal picked_up(actor: SimEntity)

var _taken: bool = false

func slot() -> StringName:
	return &"pickupable"

## A thing that could be picked up can also be thrown back out of a pocket.
func stubs() -> Array[StringName]:
	return [&"throw_item"]

## False once someone has claimed this, even if it is still in the tree.
func is_available() -> bool:
	return not _taken

## Resolves a pick-up by `actor`. The guard matters: several animals can be
## converging on the same berry, and only the first may have it.
func take(actor: SimEntity, inventory: SimInventoryComponent) -> bool:
	if _taken:
		return false
	if not inventory.store(entity.to_resource()):
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
	return {"state": "available" if is_available() else "carried"}
