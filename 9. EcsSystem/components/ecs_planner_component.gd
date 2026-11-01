class_name EcsPlannerComponent
extends EcsComponent

## The goals and actions EcsPlanningSystem plans with, and its current plan. The
## brain runs the first step; until the first plan it uses its own ladder.

## Actions it may plan with.
@export var actions: Array[EcsActionDef] = []
## Goals it may choose between.
@export var goals: Array[EcsGoalDef] = []

## Whether it has planned at least once.
var planned: bool = false
## Waiting in the replan queue.
var dirty: bool = false
## The goal being planned toward, or &"" for none.
var goal: StringName = &""
## The plan. The brain executes `steps[0]`.
var steps: Array[StringName] = []
## The facts and goal ranking the plan was made from.
var facts: Dictionary = {}
var ranking: Array[StringName] = []
## Plans made so far.
var replans: int = 0
## Planning runs left to wait after a kill, until its corpse has been seen.
var settling: int = 0

func key() -> StringName:
	return &"planner"

func describe() -> Dictionary:
	return {"tab": &"own", "lines": {
		"goal": String(goal) if goal != &"" else "—",
		"plan": " > ".join(steps) if not steps.is_empty() else "—",
	}}
