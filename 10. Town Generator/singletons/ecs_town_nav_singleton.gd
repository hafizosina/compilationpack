class_name EcsTownNavSingleton
extends EcsSingleton

## Where a walker can step on the town grid, and the orders waiting to send walkers somewhere.
## `astar` is an index derived from the grid, kept by EcsTownNavSystem alone; the grid stays the truth.

## Solid cells and step costs, one point per cell; empty until the nav system's first run.
var astar: AStarGrid2D = AStarGrid2D.new()
## Bumped whenever a cell's walkability or cost changes, so paths know to check themselves.
var revision: int = 0
## "Go to this cell" for every selected walker, oldest first; EcsPathSystem drains it.
var orders: Array[Vector2i] = []

func key() -> StringName:
	return &"town_nav"
