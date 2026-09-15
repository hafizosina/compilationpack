class_name EcsSelectedComponent
extends EcsComponent

## Tag: this is the entity the inspector is showing. Carries no data — presence
## is the fact, and at most one entity holds it.
##
## Selection being a component rather than a variable somewhere is what lets the
## marker and the inspector both find it with an ordinary query, neither of them
## holding a reference to an entity or knowing how the pick was made.

func key() -> StringName:
	return &"selected"
