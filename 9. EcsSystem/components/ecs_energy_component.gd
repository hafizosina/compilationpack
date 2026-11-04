class_name EcsEnergyComponent
extends EcsComponent

## How rested it is. Drains while awake, refills while asleep.

## Fully rested.
@export var max_energy: float = 100.0
## Drain per second while awake.
@export var drain_idle: float = 0.5
## Extra drain per second while moving.
@export var drain_moving: float = 1.0
## Energy regained per second while asleep or collapsed.
@export var restore: float = 1.0
## Energy regained per second while hidden. 0 hiding still drains.
@export var hide_restore: float = 0.0
## At or below this the brain may choose to sleep.
@export var rest_at: float = 30.0
## A chosen sleep ends here. Keep well above `rest_at`.
@export var wake_at: float = 100.0
## A collapse ends here. Keep below `wake_at`.
@export var collapse_release: float = 50.0
## Health lost once when it collapses.
@export var collapse_damage: float = 20.0
## Starting energy is rolled in this range, as a fraction of `max_energy`.
@export_range(0.0, 1.0) var start_min: float = 1.0
@export_range(0.0, 1.0) var start_max: float = 1.0

## Current energy.
var value: float = 100.0
## Whether the starting value has been rolled. Set true in a placement that
## authors `value`, or the roll overwrites it.
var rolled: bool = false

func key() -> StringName:
	return &"energy"

func describe() -> Dictionary:
	return {"tab": &"entity", "lines": {},
		"bars": [{"label": "energy", "value": value, "max": max_energy, "tone": &"energy"}]}
