class_name EcsHealthComponent
extends EcsComponent

## What it has left before it dies.
##
## Nothing regenerates it. The only thing that spends it today is starvation,
## and a regen rule would simply undo that — so this stays a number that goes
## one way until there is a second source of damage worth healing from. The
## combat layer that used to provide one is in git at `928b9d1`.
##
## Carrying this component is the whole of "this entity can die". Anything
## without it cannot be killed by the simulation, which is why a berry bush
## starves to death nowhere.

## Full health, for the inspector and for anything that later heals.
@export var max_health: float = 100.0

## What is left. Authored so a blueprint can spawn something wounded.
@export var value: float = 100.0

func key() -> StringName:
	return &"health"
