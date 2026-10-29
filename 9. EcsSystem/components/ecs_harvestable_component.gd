class_name EcsHarvestableComponent
extends EcsComponent

## Something a creature can harvest, like a bush of berries. EcsHarvestSystem
## regrows its stock and turns a harvest into an item on the ground.

## Blueprint id a harvest yields.
@export var yields: StringName = &"berry"
## The diet of what it yields, so the brain needn't look the blueprint up.
@export var diet: StringName = &"plant"
## Most units it holds.
@export var stock_max: int = 3
## Seconds to regrow one unit.
@export var regrow: float = 10.0
## Seconds of harvesting per unit.
@export var harvest_time: float = 1.0

## Units ready to harvest.
var stock: int = 0
## Seconds until the next unit regrows.
var regrow_left: float = 0.0
## Whether it has been filled to `stock_max`. It starts full.
var stocked: bool = false

func key() -> StringName:
	return &"harvestable"

func describe() -> Dictionary:
	return {"tab": &"own", "lines": {"stock": "%d/%d" % [stock, stock_max]}}
