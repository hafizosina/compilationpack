class_name WorldGroupDef
extends Resource

## A group of buildings (home, elite, faith…) and what it wants near or away from it: other groups,
## or places (the plaza, main roads, water, the outskirts). Plots are pulled toward what their group
## likes and pushed from what it dislikes (quarters, BETTER_TOWNS_PLAN.md §1).

@export var key: StringName = &""
## Groups or place rules (WorldPlotPlanner.RULES) it wants near.
@export var likes: Array[StringName] = []
## Groups or place rules it wants away from.
@export var dislikes: Array[StringName] = []
