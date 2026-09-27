extends RefCounted

## Presenter for EcsHealthComponent: its reading against its ceiling, on the
## Entity tab.

static func present(component: EcsComponent) -> Dictionary:
	var health := component as EcsHealthComponent
	return {"tab": &"entity",
		"lines": {"health": "%d/%d" % [roundi(health.value), roundi(health.max_health)]}}
