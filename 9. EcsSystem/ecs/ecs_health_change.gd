class_name EcsHealthChange
extends RefCounted

## One instant health change that isn't a hit. Amount 0 only asks for a recheck.

var to: int = EcsWorld.NO_ENTITY
## Health added; negative hurts.
var amount: float = 0.0
var from: int = EcsWorld.NO_ENTITY
## Death detail if this change kills, such as &"collapsed".
var cause: StringName = &""
