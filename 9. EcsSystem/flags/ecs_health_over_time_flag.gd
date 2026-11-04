class_name EcsHealthOverTimeFlag
extends EcsFlag

## Base of every health-over-time effect. EcsHealthSystem applies `rate` while the
## flag is on, and removes a timed one when `left` runs out; an untimed one is
## removed by the system that raised it.

## Health per second; negative hurts.
var rate: float = 0.0
## Seconds left; INF until its owner removes it.
var left: float = INF
