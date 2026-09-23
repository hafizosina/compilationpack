class_name EcsHungerComponent
extends EcsComponent

## How hungry it is, and at what points that starts to matter.
##
## The bar is the *reason* the rest of the loop exists. Before it, a creature
## foraged because EcsLowBrainSystem's food rung said to and stopped when its
## bag was full — motion with no motive. Now the rung asks this first, so
## gathering is something a hungry animal does and a full one does not.
##
## `value` counts **up**: 0 is sated, `max_value` is starving. Counting up is
## what makes the thresholds read as "hungrier than", which is how the brain
## asks about them.
##
## Carrying this component is the whole of "this entity needs to eat". A berry
## bush has none and no rung ever asks.

## How fast hunger climbs, in points per second.
@export var rate: float = 2.0
## Starving. Sitting here is what starts costing health.
@export var max_value: float = 100.0
## Hungry enough to go and fetch food it can see. The brain's SEEK_FOOD rung
## declines below this, so a sated creature wanders past a berry.
@export var forage_at: float = 35.0
## Hungry enough to eat what it is already carrying.
##
## Deliberately *above* `forage_at`: it gathers while peckish, carries, and eats
## when properly hungry, so both rungs are visible in play. Put it below
## `forage_at` instead and a creature eats the moment it picks something up —
## an authored value, not a code change.
@export var eat_at: float = 60.0
## Health lost per second while pinned at `max_value`. Starving does nothing at
## all to an entity with no EcsHealthComponent.
@export var starve_damage: float = 5.0

## Current hunger. Runtime state: 0 sated, `max_value` starving.
var value: float = 0.0

func key() -> StringName:
	return &"hunger"
