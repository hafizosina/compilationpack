extends RefCounted

## Presenter for EcsInventoryComponent: its own tab, with each carried record as
## its type and the head of its uid — enough to see the same berry go into a
## bag and come back out.

static func present(component: EcsComponent) -> Dictionary:
	var bag := component as EcsInventoryComponent
	var held := PackedStringArray()
	for record in bag.items:
		held.append("%s (%s)" % [record.type_id, record.uid.left(6)])
	return {"tab": &"own", "lines": {
		"capacity": str(bag.capacity),
		"items": ", ".join(held) if not held.is_empty() else "—",
	}}
