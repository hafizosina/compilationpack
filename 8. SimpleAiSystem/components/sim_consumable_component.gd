class_name SimConsumableComponent
extends SimComponent

## Target-side affordance: this entity can be consumed. Nothing maps an id to a
## value — an entity is consumable because it carries this component, and how
## nourishing it is lives here with it.
##
## Offers the `consume` stub, so a holder can ask "what can I do with this?"
## without knowing what it is.
##
## This is the WORLD side, and it does exactly one thing: hand over a blueprint
## snapshot of itself and leave the world. It deliberately does NOT apply the
## nourishment — eating something off the ground and eating it out of a pocket
## must have identical effects, so both go through one path in HungerComponent,
## and the number comes from SimConsumableDef either way.

signal consumed(actor: SimEntity)

var _used := false

func slot() -> StringName:
	return &"consumable"

func stubs() -> Array[StringName]:
	return [&"consume"]

func is_available() -> bool:
	return not _used

## Hands over a snapshot of this entity and removes it from the world. Returns
## null if something already claimed it — several animals can be converging on
## the same berry, and only the first may have it.
##
## The caller decides what to do with what it gets back; this only gives it up.
## That is the same shape as pick-up, which is why both can share one route.
func claim(actor: SimEntity) -> SimEntityDef:
	if _used:
		return null
	_used = true
	var snapshot := entity.to_resource()
	consumed.emit(actor)
	# Detached immediately, not just queue_free()d: a queued node stays in the
	# tree until the end of the frame, so other sensors would keep detecting a
	# berry that is already gone.
	var parent := entity.get_parent()
	if parent != null:
		parent.remove_child(entity)
	entity.queue_free()
	return snapshot

func describe() -> Dictionary:
	return {"state": "available" if is_available() else "consumed"}
