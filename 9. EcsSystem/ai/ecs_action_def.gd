class_name EcsActionDef
extends Resource

## One step the planner may take: the facts it needs and the facts it makes true.
## `id` names a brain rung that carries it out.

## The action id the brain executes.
@export var id: StringName = &""
## Facts that must hold first: fact -> bool.
@export var preconditions: Dictionary = {}
## Facts that hold after: fact -> bool.
@export var effects: Dictionary = {}
## The planner picks the cheapest plan.
@export var cost: float = 1.0
## Seconds its effects may take to come true before it has failed. 0 never fails.
@export var patience: float = 0.0
