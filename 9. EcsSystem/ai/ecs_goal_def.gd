class_name EcsGoalDef
extends Resource

## A goal the planner plans toward. EcsPlanningSystem scores it from `need`
## times `weight`; the highest-scoring goal with a plan wins.

## Shown in the inspector and the overlay.
@export var id: StringName = &""
## Facts it wants to hold: fact -> bool.
@export var desired: Dictionary = {}
## The reading it answers: &"eat", &"drink", &"provision", &"rest", &"flee" or &"breed".
@export var need: StringName = &""
## Score scale. The default weights keep the ladder's order: eat > provision > rest,
## and put flee between eating when starving and eating when merely hungry.
@export var weight: float = 1.0
