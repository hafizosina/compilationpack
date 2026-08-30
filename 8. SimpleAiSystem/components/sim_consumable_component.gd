class_name SimConsumableComponent
extends SimComponent

## Target-side affordance: this entity can be consumed. Nothing maps an id to a
## value — an entity is consumable because it carries this component, and how
## nourishing it is lives here with it.
##
## Offers the `consume` stub, so a holder can ask "what can I do with this?"
## without knowing what it is.
##
## This is the WORLD side, and it resolves consumption itself: top the eater up,
## then destroy itself. A thing that has been picked up is a blueprint snapshot
## instead, and the matching SimConsumableDef carries the same number.

## Hunger restored when consumed.
var nourishment: float = 35.0

signal consumed(actor: SimEntity)

var _used := false

func slot() -> StringName:
	return &"consumable"

func stubs() -> Array[StringName]:
	return [&"consume"]

func is_available() -> bool:
	return not _used

## Resolves being consumed by `actor`, restoring `into`. Returns false if
## something already took it.
func consume(actor: SimEntity, into: SimBarComponent) -> bool:
	if _used:
		return false
	_used = true
	into.restore(nourishment)
	consumed.emit(actor)
	var parent := entity.get_parent()
	if parent != null:
		parent.remove_child(entity)
	entity.queue_free()
	return true

func describe() -> Dictionary:
	return {
		"nourishment": "%.0f hunger" % nourishment,
		"state": "available" if is_available() else "consumed",
	}
