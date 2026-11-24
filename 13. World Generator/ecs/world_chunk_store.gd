class_name WorldChunkStore
extends RefCounted

## One map level's chunks: plans made on demand off the main thread, drawn round the view, nodes freed far
## off, plans kept up to `cap` (least recently used dropped). The level wraps east-west, so a plan is keyed
## by its wrapped chunk and a drawn node by where it is drawn.

## Cells a chunk side.
var size: int
## The level's size in chunks.
var chunks: Vector2i
## Plans kept at most.
var cap: int
## Wrapped chunk -> its plan.
var plans: Dictionary = {}
## Wrapped chunks being planned.
var busy: Dictionary = {}
## Unwrapped chunk -> its drawn node.
var drawn: Dictionary = {}
## Microseconds spent planning, and how many plans, for the report.
var plan_usec: int = 0
var planned: int = 0

var _used: Dictionary = {}
var _tick: int = 0

func _init(chunk_size: int, level_cells: Vector2i, plan_cap: int) -> void:
	size = chunk_size
	chunks = Vector2i(level_cells.x / chunk_size, level_cells.y / chunk_size)
	cap = plan_cap

## `at` with its x wrapped round the level.
func wrapped(at: Vector2i) -> Vector2i:
	return Vector2i(posmod(at.x, chunks.x), at.y)

## The chunks (unwrapped) over `cells` and `ring` more round them, nearest the middle first.
func around(cells: Rect2i, ring: int) -> Array[Vector2i]:
	var from := Vector2i(floori(float(cells.position.x) / size), floori(float(cells.position.y) / size)) - Vector2i(ring, ring)
	var to := Vector2i(floori(float(cells.end.x - 1) / size), floori(float(cells.end.y - 1) / size)) + Vector2i(ring, ring)
	var middle := (Vector2(from) + Vector2(to)) * 0.5
	var out: Array[Vector2i] = []
	for y in range(maxi(from.y, 0), mini(to.y, chunks.y - 1) + 1):
		for x in range(from.x, to.x + 1):
			out.append(Vector2i(x, y))
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(a).distance_squared_to(middle) < Vector2(b).distance_squared_to(middle))
	return out

## Marks `at`'s plan as just used.
func touch(at: Vector2i) -> void:
	_tick += 1
	_used[wrapped(at)] = _tick

## Files a finished plan.
func put(at: Vector2i, plan: Dictionary, usec: int) -> void:
	busy.erase(at)
	plans[at] = plan
	plan_usec += usec
	planned += 1
	touch(at)

## Drops the least recently used plans past `cap`, never one drawn or being made.
func trim() -> void:
	if plans.size() <= cap:
		return
	var shown: Dictionary = {}
	for at: Vector2i in drawn:
		shown[wrapped(at)] = true
	var keys: Array = plans.keys().filter(func(k: Vector2i) -> bool: return not shown.has(k))
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _used.get(a, 0) < _used.get(b, 0))
	for k: Vector2i in keys.slice(0, plans.size() - cap):
		plans.erase(k)
		_used.erase(k)
