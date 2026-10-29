class_name EcsConst
extends RefCounted

## Constants and helpers for module 9.

## Baseline travel speed in px/sec.
const WALK_SPEED: float = 90.0

## Scale applied to the ~128px animal art so one creature covers one tile.
const SPRITE_SCALE: float = 0.5

## Node kinds a component can declare with `const NODE_KIND`.
const NODE_SPRITE: StringName = &"Sprite2D"
const NODE_BODY: StringName = &"Area2dForBody"
const NODE_SENSOR: StringName = &"Area2dForSensor"
const NODE_ACTION: StringName = &"Area2dForAction"

## Physics layer bits. Only bodies have a layer, so sensors never see each other.
const LAYER_NONE: int = 0
const LAYER_BODY: int = 1

## How close to the arena edge a wander destination may be picked.
const EDGE_MARGIN: float = 48.0

## The playable area, in global pixels. Set by main.gd at startup.
static var world_bounds: Rect2 = Rect2(-1600.0, -840.0, 3200.0, 1680.0)

## A random point within `radius` of `origin`, inside the arena. `min_ratio`
## excludes an inner disc, as a fraction of `radius`.
static func random_point_near(origin: Vector2, radius: float, min_ratio: float = 0.0) -> Vector2:
	var distance := radius * sqrt(randf_range(min_ratio * min_ratio, 1.0))
	var target := origin + Vector2.RIGHT.rotated(randf() * TAU) * distance
	var inner := world_bounds.grow(-EDGE_MARGIN)
	return Vector2(
		clampf(target.x, inner.position.x, inner.end.x),
		clampf(target.y, inner.position.y, inner.end.y))
