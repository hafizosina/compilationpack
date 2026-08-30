class_name SimFoodComponent
extends SimComponent

## Target-side affordance: this entity is food. Nothing maps an id to a hunger
## value — an entity is edible because it carries this component, and how
## nourishing it is lives here with it.
##
## Actor declares, target resolves: HungerComponent asks, and this decides what
## eating actually does — top the eater up, then destroy itself.

## Hunger restored when eaten.
var hunger_value: float = 35.0

## Emitted just before the entity is consumed.
signal eaten(actor: SimEntity)

var _consumed := false

func slot() -> StringName:
	return &"food"

func is_available() -> bool:
	return not _consumed

## Resolves being eaten by `actor`. Returns false if something already ate it.
func consume(actor: SimEntity, hunger: SimBarComponent) -> bool:
	if _consumed:
		return false
	_consumed = true
	hunger.restore(hunger_value)
	eaten.emit(actor)
	var parent := entity.get_parent()
	if parent != null:
		parent.remove_child(entity)
	entity.queue_free()
	return true

func describe() -> Dictionary:
	return {
		"nourishment": "%.0f hunger" % hunger_value,
		"state": "edible" if is_available() else "eaten",
	}
