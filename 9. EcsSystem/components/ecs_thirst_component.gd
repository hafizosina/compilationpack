class_name EcsThirstComponent
extends EcsComponent

## How watered it is. `hydration` starts full and drains to zero, which costs health.

## Hydration lost per second while awake.
@export var drain: float = 0.5
## Fraction of `drain` while asleep. Keep above 0 or thirst can't wake a sleeper.
@export var asleep_drain_scale: float = 0.4
## Fully watered.
@export var max_hydration: float = 100.0
## Below this it goes looking for water.
@export var seek_water_below: float = 65.0
## Below this it drinks water within reach.
@export var drink_below: float = 70.0
## At or below this it is parched: it won't sleep, and it wakes to drink.
@export var parched_below: float = 15.0
## Health lost per second at zero hydration.
@export var dehydrate_damage: float = 5.0

## Current hydration.
var hydration: float = 100.0

func key() -> StringName:
	return &"thirst"

func describe() -> Dictionary:
	return {"tab": &"entity", "lines": {},
		"bars": [{"label": "hydration", "value": hydration, "max": max_hydration, "tone": &"hydration"}]}
