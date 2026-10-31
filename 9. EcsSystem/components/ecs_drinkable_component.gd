class_name EcsDrinkableComponent
extends EcsComponent

## Water a creature can drink from while its reach touches the body.

## Hydration a drinker gains per second.
@export var rate: float = 25.0

func key() -> StringName:
	return &"drinkable"
