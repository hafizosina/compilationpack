class_name EcsBlockingFlag
extends EcsFlag

## Guarding. Added and removed by EcsSkillSystem; EcsBlockSystem softens hits from in front.

## Share of a blocked hit's damage taken away, 0 to 1.
var reduction: float = 0.8
## Degrees around the facing it guards.
var arc: float = 140.0
