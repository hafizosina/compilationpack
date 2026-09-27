extends RefCounted

## Presenter for EcsHungerComponent: fullness against its ceiling, on the
## Entity tab.

static func present(component: EcsComponent) -> Dictionary:
	var hunger := component as EcsHungerComponent
	return {"tab": &"entity",
		"lines": {"fullness": "%d/%d" % [roundi(hunger.fullness), roundi(hunger.max_fullness)]}}
