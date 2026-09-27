class_name EcsHealthComponent
extends EcsComponent

## What it has left before it dies.
##
## It moves both ways, but never from here. EcsHungerSystem spends it while a
## creature is starving and gives it back while a creature is well fed, because
## both are hunger's consequences; this component is only the reading, and
## EcsHealthSystem owns only what happens at zero. Nothing else damages anything
## yet — the combat layer that used to is in git at `928b9d1`.
##
## Carrying this component is the whole of "this entity can die". Anything
## without it cannot be killed by the simulation, which is why a berry bush
## starves to death nowhere.

## Full health, for the inspector and for anything that later heals.
@export var max_health: float = 100.0

## What is left. Authored so a blueprint can spawn something wounded.
@export var value: float = 100.0

## How the inspector shows it — see inspect/health_inspect.gd.
const INSPECTOR := preload("res://9. EcsSystem/inspect/health_inspect.gd")

func key() -> StringName:
	return &"health"
