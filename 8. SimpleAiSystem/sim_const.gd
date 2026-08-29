class_name SimConst
extends RefCounted

## Tunable constants for the colony sim (module 8). Static-only helper class —
## deliberately NOT an autoload, since nothing outside this module reads it.

## Side length of one world tile, in pixels.
const GRID_SIZE: float = 64.0

## Baseline speeds in px/sec.
const WALK_SPEED: float = 120.0
const RUN_SPEED: float = 240.0

## Scale applied to the ~128px animal art so one creature covers one tile.
const SPRITE_SCALE: float = 0.5

## Physics layer every entity sits on, and the layer sensors query against.
const ENTITY_LAYER: int = 1

## How close to the map edge a wander destination may be picked.
const EDGE_MARGIN: float = 64.0

## Extents of the painted world, in global pixels. A fallback until main.gd
## measures the actual TileMapLayer — repaint the map and everything follows,
## with no constant to keep in sync.
static var world_bounds: Rect2 = Rect2(-704.0, -640.0, 3648.0, 2240.0)

## Reads the painted area straight off the tilemap and stores it as the world
## bounds. Called once by main.gd before the world is spawned.
static func adopt_bounds_from(layer: TileMapLayer) -> void:
	if layer == null or layer.tile_set == null:
		push_warning("SimConst: no TileMapLayer to measure; keeping fallback bounds")
		return
	var used := layer.get_used_rect()
	if used.size == Vector2i.ZERO:
		push_warning("SimConst: TileMapLayer is empty; keeping fallback bounds")
		return
	var tile: Vector2 = Vector2(layer.tile_set.tile_size)
	world_bounds = Rect2(Vector2(used.position) * tile * layer.scale,
		Vector2(used.size) * tile * layer.scale)
