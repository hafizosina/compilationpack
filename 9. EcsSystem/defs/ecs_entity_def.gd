class_name EcsEntityDef
extends Resource

## One entity blueprint — the authored answer to "what is a crocodile?".
##
## Note what is missing compared with the node-composition build: there is no
## per-component def class wrapping each component and knowing how to build it.
## A component is already pure data, so the blueprint just holds the components
## themselves and the factory copies them. The def layer lost a whole parallel
## class hierarchy the moment behaviour left the components.

## Stable lookup id, referenced by EcsPlacement.type.
@export var id: StringName = &""
## Human-readable name, for the HUD and debug listings.
@export var display_name: String = ""
## The components every instance of this type gets, copied per instance.
## What the thing *is* equals what is in this list; there is no type hierarchy.
@export var components: Array[EcsComponent] = []

## The component template under `component_key`, or null. Lets a blueprint be
## asked what it can do before anything is spawned.
func template(component_key: StringName) -> EcsComponent:
	for component in components:
		if component != null and component.key() == component_key:
			return component
	return null
