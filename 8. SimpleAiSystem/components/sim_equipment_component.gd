class_name SimEquipmentComponent
extends SimComponent

## Target-side affordance: this entity can be worn or wielded. Offers the
## `equip` stub so a holder can find it the same way it finds anything else —
## by asking which verbs a carried thing supports.
##
## DECLARED, NOT IMPLEMENTED. Nothing equips anything yet; this exists so the
## verb vocabulary is in one place rather than being invented later. No
## blueprint carries it.

## Where it goes when equipped.
var body_slot: StringName = &"hand"

func slot() -> StringName:
	return &"equipment"

func stubs() -> Array[StringName]:
	return [&"equip"]

func describe() -> Dictionary:
	return {"equips to": String(body_slot)}
