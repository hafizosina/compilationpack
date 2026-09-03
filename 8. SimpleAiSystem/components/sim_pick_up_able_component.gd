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
## thing. This adds only what is specific to carrying — the `throw_item` verb and
## the `picked_up` signal. The two affordances are deliberately the same shape,
## because an affordance is only ever a verb plus a claim.

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

## Hands over a snapshot of this entity and removes it from the world, or null if
## something already claimed it — through this door or any other.
##
## It asks the actor NOTHING. Whether there is room to carry this, and whether
## the actor is near enough to take it, are the actor's own facts and its own
## business; this component has no opinion on either and cannot see them. Since
## a claim cannot be undone, everything that could refuse must refuse before the
## actor asks — which is why the check lives where the knowledge is.
func claim(actor: SimEntity) -> SimEntityDef:
	var snapshot := entity.claim_snapshot()
	if snapshot != null:
		picked_up.emit(actor)
	return snapshot

func describe() -> Dictionary:
	return {"state": "available" if is_available() else "carried"}
