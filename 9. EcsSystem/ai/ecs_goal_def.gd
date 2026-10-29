class_name EcsGoalDef
extends Resource

## A goal the planner plans toward. EcsPlanningSystem scores it from `need`
## times `weight`; the highest-scoring goal with a plan wins.

## Shown in the inspector and the overlay.
@export var id: StringName = &""
## Facts it wants to hold: fact -> bool.
@export var desired: Dictionary = {}
## The reading it answers: &"eat", &"provision" or &"rest".
@export var need: StringName = &""
## Score scale. The default weights keep the ladder's order: eat > provision > rest.
@export var weight: float = 1.0
