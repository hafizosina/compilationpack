class_name WorldResourceDef
extends Resource

## Something a town uses or sells. The census asks how much its people need, how much its land can
## give, and so how many of its makers to build; the rest is imported.

@export var key: StringName = &""
@export var display_name: String = ""
## How much one person needs a year; 0 for a trade good, made only to sell.
@export var per_person: float = 0.0
## A trade good's export a year per person of the town, when it is the town's main trade.
@export var export_per_person: float = 0.0
## Too heavy to carry to a market stall: sold where it is made.
@export var heavy: bool = false
