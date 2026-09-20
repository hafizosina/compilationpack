class_name EcsConst
extends RefCounted

## Tunables for the ECS module. Static-only helper, deliberately NOT an
## autoload — nothing outside module 9 reads it.

## Baseline travel speed in px/sec.
const WALK_SPEED: float = 90.0

## Scale applied to the ~128px animal art so one creature covers one tile.
const SPRITE_SCALE: float = 0.5

## Node kinds a component may ask for, declared as `const NODE_KIND` on the
## component and built by EcsEntityManager.
##
## They live here rather than on either side so that neither has to import the
## other: a data component naming the manager would point the dependency
## backwards, and the manager naming components would make it switch on type.
## Both just agree on a string.
const NODE_SPRITE: StringName = &"Sprite2D"
const NODE_BODY: StringName = &"Area2dForBody"
const NODE_SENSOR: StringName = &"Area2dForSensor"
const NODE_ACTION: StringName = &"Area2dForAction"

## Physics layer bits. Only bodies occupy a layer; sensors and action areas are
## pure lookers — they carry no layer at all, so nothing detects *them*.
##
## That is the whole answer to "does perception cost n² again": a sensor is
## reported only the bodies it overlaps, never the other 499 sensors. Get this
## wrong and the n² moves out of GDScript and into the physics server, which is
## worse, because it is no longer visible in a profile you can read.
const LAYER_NONE: int = 0
const LAYER_BODY: int = 1

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
