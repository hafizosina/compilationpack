class_name EcsConsumableComponent
extends EcsComponent

## Eating this is worth `nutrition` points off the eater's hunger.
##
## It is what separates food from everything else that fits in a bag. The brain
## looks for this component when it decides to eat, so a carried rock is simply
## never chosen and needs no flag saying it is inedible.
##
## Pickable and consumable are different claims on purpose: a berry is both, a
## tool would be the first only, and a berry growing on a bush that cannot be
## carried away would be the second only.

## Points taken off EcsHungerComponent.value when this is eaten.
@export var nutrition: float = 40.0

func key() -> StringName:
	return &"consumable"
