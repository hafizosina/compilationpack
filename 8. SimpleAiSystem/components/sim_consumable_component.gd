class_name SimConsumableComponent
extends SimComponent

## Target-side affordance: this entity can be consumed. Nothing maps an id to a
## value — an entity is consumable because it carries this component, and the
## amount lives on SimConsumableDef, which is the only place it lives.
##
## Offers the `consume` stub, so a holder can ask "what can I do with this?"
## without knowing what it is.
##
## This is the WORLD side, and it is a DOOR, not a mechanism: winning the entity
## belongs to SimEntity.claim_snapshot(), which every affordance shares. This
## adds only what is specific to eating — the `consume` verb and the `consumed`
## signal. It deliberately does NOT apply the nourishment: eating off the ground
## and eating out of a pocket must have identical effects, so both hand the same
## snapshot to HungerComponent and the number is read from the def either way.

## Emitted once this entity has been consumed by `actor`.
signal consumed(actor: SimEntity)

func slot() -> StringName:
	return &"consumable"

func stubs() -> Array[StringName]:
	return [&"consume"]

func is_available() -> bool:
	return entity != null and not entity.is_claimed()

## Hands over a snapshot of this entity and removes it from the world, or null if
## something already claimed it — through this door or any other.
##
## The caller decides what to do with what it gets back; this only gives it up.
func claim(actor: SimEntity) -> SimEntityDef:
	var snapshot := entity.claim_snapshot()
	if snapshot != null:
		consumed.emit(actor)
	return snapshot

func describe() -> Dictionary:
	return {"state": "available" if is_available() else "consumed"}
