class_name EcsInventoryComponent
extends EcsComponent

## Somewhere to put what gets collected.
##
## It holds **records**, not entities. Picking something up kills it and keeps
## an EcsItemRecord — every component it had, and its uid — so it can be eaten
## from here or put back into the world as itself.
##
## This is a reversal, made knowingly. Step 3 kept carried items as live
## entities, for the weapon pain case: module 8 snapshotted and destroyed on
## pickup, and a carried thing became a recipe for itself. Records are that
## again, on purpose — in most games an item in a bag is not a live entity — and
## what a carried item should *do* while carried (durability, rot) is deferred
## until something needs it. See EcsItemRecord.
##
## Having one of these is what makes an entity forage. No inventory, and the
## brain's food rung declines to run, so a berry bush never goes looking for
## berries and nothing had to tell it not to.

## How many records fit. One item, one slot; stacking is for later.
@export var capacity: int = 1

## What is held. Runtime state.
var items: Array[EcsItemRecord] = []

func key() -> StringName:
	return &"inventory"

## How the inspector shows it: its own tab, each carried record as its type and
## the head of its uid. Display only; see EcsComponent.describe().
func describe() -> Dictionary:
	var held := PackedStringArray()
	for record in items:
		held.append("%s (%s)" % [record.type_id, record.uid.left(6)])
	return {"tab": &"own", "lines": {
		"capacity": str(capacity),
		"items": ", ".join(held) if not held.is_empty() else "—",
	}}
