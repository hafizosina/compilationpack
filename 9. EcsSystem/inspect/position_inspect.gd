extends RefCounted

## Presenter for EcsPositionComponent: one line on the Entity tab.

static func present(component: EcsComponent) -> Dictionary:
	var place := (component as EcsPositionComponent).position
	return {"tab": &"entity", "lines": {"position": "(%.0f, %.0f)" % [place.x, place.y]}}
