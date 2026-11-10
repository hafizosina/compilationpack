class_name EcsSettlementCharacterDef
extends Resource

## What a town may live on: how its survey scores it, what it builds as the town's main trade, and
## the small operation it adds when it is only a side line.

@export var key: StringName = &""
@export var display_name: String = ""
## The smallest tier it can be the main trade of.
@export_enum("Hamlet", "Village", "Town", "City", "Great City") var min_tier: int = 0
## Its score: the sum of survey scores times these weights.
@export var weights: Dictionary[StringName, float] = {}
## Survey facts it can't do without; one of `requires_any` too, when it lists any.
@export var requires: Array[StringName] = []
@export var requires_any: Array[StringName] = []
## Role key -> count range, built when it is the main trade, scaled by the tier.
@export var core: Dictionary[StringName, Vector2i] = {}
## Role key -> count range, built when it is a side line.
@export var side: Dictionary[StringName, Vector2i] = {}
## A score at least this makes it a side line when it isn't the main trade.
@export var side_at: float = 0.5
