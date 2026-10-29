class_name EcsEntityDef
extends Resource

## One entity blueprint: an id and the components every instance gets.

## Stable lookup id, referenced by EcsPlacement.type.
@export var id: StringName = &""
## Human-readable name, for the HUD and debug listings.
@export var display_name: String = ""
## The components every instance gets, copied per instance.
@export var components: Array[EcsComponent] = []

## The component template under `component_key`, or null.
func template(component_key: StringName) -> EcsComponent:
	for component in components:
		if component != null and component.key() == component_key:
			return component
	return null
