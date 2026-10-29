class_name EcsInventoryComponent
extends EcsComponent

## A bag of item records. One record per slot.

## How many records fit.
@export var capacity: int = 1

## What is held.
var items: Array[EcsItemRecord] = []

func key() -> StringName:
	return &"inventory"

func describe() -> Dictionary:
	var held := PackedStringArray()
	for record in items:
		held.append("%s (%s)" % [record.type_id, record.uid.left(6)])
	return {"tab": &"own", "lines": {
		"capacity": str(capacity),
		"items": ", ".join(held) if not held.is_empty() else "—",
	}}
