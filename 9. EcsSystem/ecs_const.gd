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
static var world_bounds: Rect2 = Rect2(-1600.0, -840.0, 3200.0, 1680.0)

## A point within `radius` of `origin`, kept inside the arena.
##
## `min_ratio` excludes an inner disc: the low brain passes 0.25 so a creature
## never picks a destination it is already standing on, while a spawner passes
## 0 to scatter evenly. The sqrt is what makes the scatter uniform by *area* —
## without it everything clusters toward the middle.
##
## It lives here rather than in either caller because the bounds rule has one
## home, and it grew this parameter the moment a second caller wanted it.
static func random_point_near(origin: Vector2, radius: float, min_ratio: float = 0.0) -> Vector2:
	var distance := radius * sqrt(randf_range(min_ratio * min_ratio, 1.0))
	var target := origin + Vector2.RIGHT.rotated(randf() * TAU) * distance
	var inner := world_bounds.grow(-EDGE_MARGIN)
	return Vector2(
		clampf(target.x, inner.position.x, inner.end.x),
		clampf(target.y, inner.position.y, inner.end.y))
