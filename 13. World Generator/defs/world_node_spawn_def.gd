class_name WorldNodeSpawnDef
extends Resource

## Where and how thickly one kind of resource node grows on a generated map.

## Where a node may grow.
enum Zone { MEADOW, FOREST, FOREST_EDGE, DEEP_FOREST, ROCK, ROCK_INNER, SHORE, SHALLOW }

## The node's blueprint in module 10's entity catalog.
@export var blueprint: StringName = &""
@export var zone: Zone = Zone.MEADOW
## Chance a free cell of its zone starts one.
@export var density: float = 0.05
## Nodes in a clump: 1 scatters them; more grows a vein or a grove from each start.
@export var cluster: int = 1
## Free cells kept round each node, so nodes never wall a way off.
@export var keep_clear: int = 0
## The deposit it grows in (WorldDepositDef.key), or empty for anywhere in its zone. On a map
## with no deposits (one planned on its own) it grows anywhere in its zone.
@export var deposit: StringName = &""
## Fewest the map must have: the generator tops up to it while the zone has room.
@export var min_count: int = 1
