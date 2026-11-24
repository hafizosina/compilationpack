class_name WorldSettlementCharacterDef
extends Resource

## What a town may live on: how its survey scores it, and which maker's work it exports.

@export var key: StringName = &""
@export var display_name: String = ""
## The smallest tier it can be the main trade of.
@export_enum("Hamlet", "Village", "Town", "City", "Great City") var min_tier: int = 0
## Its score: the sum of survey scores times these weights.
@export var weights: Dictionary[StringName, float] = {}
## Survey facts it can't do without; one of `requires_any` too, when it lists any.
@export var requires: Array[StringName] = []
@export var requires_any: Array[StringName] = []
## The role whose work the town sells; empty for a town that lives on passing trade.
@export var exports: StringName = &""
## Traffic levels added: a trading town sees more travellers.
@export var traffic_bonus: int = 0
