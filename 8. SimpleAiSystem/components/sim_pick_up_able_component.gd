class_name SimPickUpAbleComponent
extends SimComponent

## Target-side affordance: this entity can be picked up.
##
## Being carried DOES remove the entity from the world: the carrier keeps a
## blueprint snapshot of it and the node destroys itself, so nothing sits hidden
## in the scene tree still running its components. What a carried thing can do is
## still decided by which component defs the snapshot holds — the same rule as
## everything else, asked of a blueprint instead of a live node.
##
## Like SimConsumableComponent this is a DOOR, not a mechanism: leaving the world
## belongs to SimEntity.claim_snapshot(), shared by every affordance that takes a
## thing. This adds only what is specific to carrying.

## Emitted once this entity has been taken by `actor`.
signal picked_up(actor: SimEntity)

func slot() -> StringName:
	return &"pickupable"

## A thing that could be picked up can also be thrown back out of a pocket.
func stubs() -> Array[StringName]:
	return [&"throw_item"]

## False once someone has claimed this, through this door or any other.
func is_available() -> bool:
	return entity != null and not entity.is_claimed()

## Resolves a pick-up by `actor`, into `inventory`.
##
## Capacity is checked BEFORE the entity gives itself up, because
## claim_snapshot() is irreversible: a full inventory that claimed first would
## destroy the thing and store nothing.
func take(actor: SimEntity, inventory: SimInventoryComponent) -> bool:
	if inventory == null or inventory.is_full():
		return false
	var snapshot := entity.claim_snapshot()
	if snapshot == null:
		return false
	inventory.store(snapshot)
	picked_up.emit(actor)
	return true

func describe() -> Dictionary:
	return {"state": "available" if is_available() else "carried"}
