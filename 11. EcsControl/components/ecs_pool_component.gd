class_name EcsPoolComponent
extends EcsComponent

## A reserve that is spent and refills. Only EcsPoolSystem writes `value`; others ask by
## adding to `spent`.

@export var max_value: float = 100.0
@export var value: float = 100.0
## Refill per second.
@export var regen: float = 20.0
## Seconds after spending before it refills.
@export var regen_delay: float = 0.8

## Asked for since the last run.
var spent: float = 0.0
## Seconds since it was last spent.
var since_spent: float = 1000.0
