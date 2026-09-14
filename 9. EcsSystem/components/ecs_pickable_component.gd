class_name EcsPickableComponent
extends EcsComponent

## Tag: this can be picked up. Carries no data — presence is the fact.
##
## It is what separates a berry from a berry bush. Both are entities with a
## sprite sitting in the world; only one of them answers the forager's query.
## No `is_item` flag, no type check, no layer mask.

func key() -> StringName:
	return &"pickable"
