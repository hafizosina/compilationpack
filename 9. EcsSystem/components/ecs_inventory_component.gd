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

## How the inspector shows it — see inspect/inventory_inspect.gd.
const INSPECTOR := preload("res://9. EcsSystem/inspect/inventory_inspect.gd")

func key() -> StringName:
	return &"inventory"
