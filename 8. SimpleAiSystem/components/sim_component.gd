class_name SimComponent
extends Node2D

## Base for every runtime behaviour component. Resolves its owning entity from
## its parent, mirroring Global/Scene/component.gd. Subclasses MUST call
## `super()` from their own `_ready()`.
##
## Components are dumb state holders. They talk to each other only *through* the
## entity (`entity.get_component(...)`) — never by hard-pathing to a sibling.

var entity: SimEntity

func _ready() -> void:
	var parent := get_parent()
	if parent is SimEntity:
		entity = parent
	else:
		push_error("%s must be a child of a SimEntity" % get_class())

## Slot key this component occupies on its entity. Override in every subclass;
## must match the matching SimComponentDef.slot().
func slot() -> StringName:
	return &""

## How this component represents ITSELF in the entity inspector: readable
## field -> value pairs, already formatted as strings so the UI stays a dumb
## renderer. Dictionaries keep insertion order, so the component also decides
## the order its fields appear in. Return {} to stay out of the panel entirely.
##
## Nothing outside the component knows what it holds — adding a component kind
## adds its own section to the inspector with no change to SimEntity or the UI.
func describe() -> Dictionary:
	return {}

## Heading this component appears under in the inspector. Defaults to the slot
## name; override to present something other than the raw key.
func describe_label() -> String:
	return String(slot()).capitalize()
