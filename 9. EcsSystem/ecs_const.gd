class_name EcsConst
extends RefCounted

## Tunables for the ECS module. Static-only helper, deliberately NOT an
## autoload — nothing outside module 9 reads it.

## Baseline travel speed in px/sec.
const WALK_SPEED: float = 90.0

## Scale applied to the ~128px animal art so one creature covers one tile.
const SPRITE_SCALE: float = 0.5

## How close to the arena edge a wander destination may be picked.
const EDGE_MARGIN: float = 48.0

## Extents of the playable area, in global pixels. main.gd overwrites this from
## its exported `arena` rect at startup, so moving the ground plate moves the
## wander bounds with it and there is no constant to keep in sync.
static var world_bounds: Rect2 = Rect2(-800.0, -420.0, 1600.0, 840.0)

## A point within `radius` of `origin`, kept inside the arena. Used by the
## wander system; kept here so the bounds rule has one home.
static func wander_point(origin: Vector2, radius: float) -> Vector2:
	var target := origin + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(radius * 0.25, radius)
	var inner := world_bounds.grow(-EDGE_MARGIN)
	return Vector2(
		clampf(target.x, inner.position.x, inner.end.x),
		clampf(target.y, inner.position.y, inner.end.y))
