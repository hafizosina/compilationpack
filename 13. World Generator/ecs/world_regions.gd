class_name WorldRegions
extends RefCounted

## The L2 regions of a world and what each has: its plan (refined from an L3 window), its drawing.
## Plans are kept, so a region is never planned twice. Says what to do next: the regions in view,
## nearest the view's centre first, every plan before any drawing.

enum Stage { PLAN, DRAW }

## L3 cells per region.
var window: Vector2i
## Regions across the world.
var count: Vector2i
## Region -> {plan, shares, drawn, level, busy}; a missing key means not yet.
var regions: Dictionary = {}

func _init(world_size: Vector2i, region_window: Vector2i) -> void:
	window = region_window
	count = Vector2i(ceili(world_size.x / float(window.x)), ceili(world_size.y / float(window.y)))

## The region holding L3 cell `cell`.
func region_at(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(cell.x / float(window.x)), floori(cell.y / float(window.y)))

## The regions over `view` (L3 cells), nearest its centre first.
func around(view: Rect2i) -> Array[Vector2i]:
	var first := region_at(view.position).clamp(Vector2i.ZERO, count - Vector2i.ONE)
	var last := region_at(view.end - Vector2i.ONE).clamp(Vector2i.ZERO, count - Vector2i.ONE)
	var centre := Vector2(view.get_center()) / Vector2(window) - Vector2(0.5, 0.5)
	var out: Array[Vector2i] = []
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			out.append(Vector2i(x, y))
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(a).distance_squared_to(centre) < Vector2(b).distance_squared_to(centre))
	return out

## The next {region, stage} for `view`, or {} when there is nothing to do.
func next_job(view: Rect2i) -> Dictionary:
	var order := around(view)
	for stage in Stage.size():
		for at in order:
			var region: Dictionary = regions.get(at, {})
			if not region.get("busy", false) and _needs(region, stage):
				return {"region": at, "stage": stage}
	return {}

## Drawn regions more than `keep` regions outside `view`, to free their nodes; their plans stay.
func far(view: Rect2i, keep: int) -> Array[Vector2i]:
	var first := region_at(view.position)
	var near := Rect2i(first, region_at(view.end - Vector2i.ONE) - first + Vector2i.ONE).grow(keep)
	var out: Array[Vector2i] = []
	for at: Vector2i in regions:
		if regions[at].get("drawn", false) and not regions[at].get("busy", false) and not near.has_point(at):
			out.append(at)
	return out

## True when region `at` is planned.
func planned(at: Vector2i) -> bool:
	return (regions.get(at, {}) as Dictionary).has("plan")

## How many regions are [planned, drawn].
func tally() -> Array[int]:
	var out: Array[int] = [0, 0]
	for at: Vector2i in regions:
		out[0] += 1 if regions[at].has("plan") else 0
		out[1] += 1 if regions[at].get("drawn", false) else 0
	return out

func _needs(region: Dictionary, stage: int) -> bool:
	match stage:
		Stage.PLAN:
			return not region.has("plan")
		Stage.DRAW:
			return region.has("plan") and not region.get("drawn", false)
	return false
