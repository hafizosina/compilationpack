extends RefCounted

## Presenter for EcsNameComponent: it names the panel, and puts only the entity
## name and its blueprint on the Entity tab. Type id and uid stay unshown.

static func present(component: EcsComponent) -> Dictionary:
	var named := component as EcsNameComponent
	return {
		"tab": &"entity",
		"title": {"name": String(named.entity_name), "type": String(named.type_id)},
		"lines": {"entity_name": String(named.entity_name), "blueprint": named.display_name},
	}
