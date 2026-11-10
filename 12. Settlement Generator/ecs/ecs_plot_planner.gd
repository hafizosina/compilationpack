class_name EcsPlotPlanner
extends RefCounted

## Pure and seeded: a town's plots and the lanes they need, added to its EcsSettlementSite.
##   1. Plots: grid-aligned footprints round the plaza and beside the main roads, thinning outwards,
##      a gap apart; each faces the side nearest a road, its door in the middle of that side.
##   2. Lanes: from the cell before each door to the nearest road, nearest plot first, so a lane
##      routed is road for the next and neighbours' lanes merge. A plot no lane reaches is dropped.
##   3. Yards: every plot grows out from its footprint, a ring at a time, over free land, until it
##      meets a road, a neighbour's yard or `yard_depth`.
## Footprints and yards go into `cleared_cells`; floors are left to EcsRoadPlanner.lay.

enum Use { FREE, ROAD, WATER, FOOTPRINT }

const SIDES: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
## Placement attempts per plot wanted.
const TRIES: int = 40
## Share of attempts made beside a main road; the rest round the plaza.
const ROADSIDE: float = 0.5
## Cells kept between a footprint and the area's edge.
const EDGE: int = 3
## How much the lanes' noise adds to a step, so they bend.
const BEND: float = 0.6

## Adds plots, their lanes and yards to `site`, `kinds` being its area's refined ground.
static func plan(site: EcsSettlementSite, def: EcsSettlementDef, kinds: PackedByteArray, rng_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([rng_seed, site.l2_cell, &"plots"])
	var area := site.area
	var use := PackedByteArray()
	use.resize(area.size.x * area.size.y)
	for i in use.size():
		if kinds[i] == EcsTerrainGenerator.WATER:
			use[i] = Use.WATER
	for cell: Vector2i in site.road_cells:
		if area.has_point(cell):
			use[_i(cell, area)] = Use.ROAD
	for y in range(site.plaza.position.y, site.plaza.end.y):
		for x in range(site.plaza.position.x, site.plaza.end.x):
			use[_i(Vector2i(x, y), area)] = Use.ROAD
	var reach := _reach(use, area.size)
	_place(site, def, use, reach, rng)
	_lanes(site, def, use, kinds, reach, rng_seed)
	_yards(site, def, use)
	for k in site.plots.size():
		var rect: Rect2i = site.plots[k]["footprint"]
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				site.plot_at[Vector2i(x, y)] = k
				site.cleared_cells[Vector2i(x, y)] = true
		for cell: Vector2i in site.plots[k]["yard"]:
			site.plot_at[cell] = k
			site.cleared_cells[cell] = true

static func _i(cell: Vector2i, area: Rect2i) -> int:
	return (cell.y - area.position.y) * area.size.x + cell.x - area.position.x

## Steps from every free cell to the nearest road or plaza cell, 4-way; -1 where none is reached.
static func _reach(use: PackedByteArray, size: Vector2i) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(size.x * size.y)
	out.fill(-1)
	var queue := PackedInt32Array()
	for i in use.size():
		if use[i] == Use.ROAD:
			out[i] = 0
			queue.append(i)
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var at := Vector2i(i % size.x, i / size.x)
		for side in SIDES:
			var next := at + side
			if next.x < 0 or next.y < 0 or next.x >= size.x or next.y >= size.y:
				continue
			var n := next.y * size.x + next.x
			if out[n] == -1 and use[n] == Use.FREE:
				out[n] = out[i] + 1
				queue.append(n)
	return out

## Footprints round the plaza and beside the main roads, densest near the centre, until `def.plots`
## are placed or the attempts run out.
static func _place(site: EcsSettlementSite, def: EcsSettlementDef, use: PackedByteArray, reach: PackedInt32Array,
		rng: RandomNumberGenerator) -> void:
	var area := site.area
	var inner := area.grow(-EDGE)
	var centre := Vector2(site.plaza.get_center())
	var far := minf(area.size.x, area.size.y) * 0.5 - EDGE
	# Main road points inside the area, from the plaza outwards, each with its road's normal.
	var roadside: Array = []
	for road in site.roads:
		if road["kind"] != &"main":
			continue
		var points := road["points"] as PackedVector2Array
		for k in range(1, points.size()):
			if inner.has_point(Vector2i(points[k].round())) and not site.plaza.has_point(Vector2i(points[k].round())):
				roadside.append([points[k], (points[k] - points[k - 1]).normalized().orthogonal()])
	var want := rng.randi_range(def.plots.x, def.plots.y)
	for attempt in want * TRIES:
		if site.plots.size() >= want:
			return
		var at := Vector2.ZERO
		if not roadside.is_empty() and rng.randf() < ROADSIDE:
			var pick: Array = roadside[int(pow(rng.randf(), 1.5) * roadside.size())]
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			at = (pick[0] as Vector2) + (pick[1] as Vector2) * side * rng.randf_range(def.main_width + 2.0, def.main_width + 8.0)
		else:
			var r := Vector2(site.plaza.size).length() * 0.5 + pow(rng.randf(), 1.5) * far
			at = centre + Vector2.from_angle(rng.randf() * TAU) * r
		var t := clampf(at.distance_to(centre) / far, 0.0, 1.0)
		var low := roundi(lerpf(def.plot_size_centre.x, def.plot_size_edge.x, t))
		var high := roundi(lerpf(def.plot_size_centre.y, def.plot_size_edge.y, t))
		var size := Vector2i(rng.randi_range(low, high), rng.randi_range(low, high))
		var rect := Rect2i(Vector2i(at.round()) - size / 2, size)
		if not inner.encloses(rect) or not _fits(rect, use, area, def.plot_gap):
			continue
		var front := _front(rect, use, reach, area)
		if front == Vector2i.ZERO:
			continue
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				use[_i(Vector2i(x, y), area)] = Use.FOOTPRINT
		site.plots.append({"footprint": rect, "front": front, "door": _door(rect, front), "yard": []})

## Whether `rect` stands on free land with land round it and `gap` cells clear of other footprints.
static func _fits(rect: Rect2i, use: PackedByteArray, area: Rect2i, gap: int) -> bool:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if use[_i(Vector2i(x, y), area)] != Use.FREE:
				return false
	var ring := rect.grow(1).intersection(area)
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, ring.end.x):
			if use[_i(Vector2i(x, y), area)] == Use.WATER:
				return false
	var room := rect.grow(gap).intersection(area)
	for y in range(room.position.y, room.end.y):
		for x in range(room.position.x, room.end.x):
			if use[_i(Vector2i(x, y), area)] == Use.FOOTPRINT:
				return false
	return true

## The side of `rect` whose door would be nearest a road, or zero when no side can reach one.
static func _front(rect: Rect2i, use: PackedByteArray, reach: PackedInt32Array, area: Rect2i) -> Vector2i:
	var best := Vector2i.ZERO
	var nearest := -1
	for side in SIDES:
		var outside := _door(rect, side) + side
		if not area.has_point(outside):
			continue
		var i := _i(outside, area)
		var steps := reach[i]
		if use[i] == Use.ROAD:
			steps = 0
		if steps >= 0 and (nearest < 0 or steps < nearest):
			nearest = steps
			best = side
	return best

## The middle cell of `rect`'s side facing `side`.
static func _door(rect: Rect2i, side: Vector2i) -> Vector2i:
	var mid := rect.position + rect.size / 2
	match side:
		Vector2i.RIGHT:
			return Vector2i(rect.end.x - 1, mid.y)
		Vector2i.LEFT:
			return Vector2i(rect.position.x, mid.y)
		Vector2i.DOWN:
			return Vector2i(mid.x, rect.end.y - 1)
	return Vector2i(mid.x, rect.position.y)

## A lane from each plot's door to the nearest road, nearest plot first; plots none reaches are
## dropped and their footprints freed.
static func _lanes(site: EcsSettlementSite, def: EcsSettlementDef, use: PackedByteArray, kinds: PackedByteArray,
		reach: PackedInt32Array, rng_seed: int) -> void:
	var area := site.area
	var bend := FastNoiseLite.new()
	bend.seed = hash([rng_seed, &"lanes"])
	bend.frequency = 0.15
	var order: Array[Dictionary] = site.plots.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return reach[_i(a["door"] + a["front"], area)] < reach[_i(b["door"] + b["front"], area)])
	var kept: Array[Dictionary] = []
	for plot in order:
		var start: Vector2i = plot["door"] + plot["front"]
		if use[_i(start, area)] == Use.ROAD:
			kept.append(plot)
			continue
		var path := _route(start, use, kinds, reach, area, def, bend)
		if path.is_empty():
			var rect: Rect2i = plot["footprint"]
			for y in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					use[_i(Vector2i(x, y), area)] = Use.FREE
			continue
		var points := PackedVector2Array()
		for k in path.size():
			var cell := path[k]
			points.append(Vector2(cell))
			# A diagonal step takes a side cell too, so the lane is joined edge to edge.
			if k > 0 and cell.x != path[k - 1].x and cell.y != path[k - 1].y:
				_take(site, use, area, Vector2i(cell.x, path[k - 1].y))
			if k < path.size() - 1:
				_take(site, use, area, cell)
		site.roads.append({"kind": &"lane", "points": points, "width": def.lane_width})
		kept.append(plot)
	# Back in placement order, so the same seed lists the same plots.
	site.plots = site.plots.filter(func(p: Dictionary) -> bool: return kept.has(p))

static func _take(site: EcsSettlementSite, use: PackedByteArray, area: Rect2i, cell: Vector2i) -> void:
	use[_i(cell, area)] = Use.ROAD
	if not site.road_cells.has(cell):
		site.road_cells[cell] = &"lane"

## A cheap 8-way route from `start` to a road cell, no dearer than `lane_reach`, over land and round
## footprints, cutting no corner, searched toward the nearest road by `reach`; its cells, the road
## cell it meets last. Empty when none.
static func _route(start: Vector2i, use: PackedByteArray, kinds: PackedByteArray, reach: PackedInt32Array, area: Rect2i,
		def: EcsSettlementDef, bend: FastNoiseLite) -> Array[Vector2i]:
	var inner := area.grow(-1)
	var cost: Dictionary = {start: 0.0}
	var came: Dictionary = {}
	var closed: Dictionary = {}
	var heap_cost := PackedFloat32Array([0.0])
	var heap_cell := PackedInt32Array([_i(start, area)])
	while not heap_cost.is_empty():
		var at := Vector2i(heap_cell[0] % area.size.x, heap_cell[0] / area.size.x) + area.position
		EcsRoadPlanner.heap_pop(heap_cost, heap_cell)
		if closed.has(at):
			continue
		closed[at] = true
		var c: float = cost[at]
		if use[_i(at, area)] == Use.ROAD:
			var path: Array[Vector2i] = [at]
			while came.has(path[0]):
				path.push_front(came[path[0]])
			return path
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var next := at + Vector2i(dx, dy)
				if not inner.has_point(next) or not _open(use, area, next):
					continue
				if dx != 0 and dy != 0 and not (_open(use, area, at + Vector2i(dx, 0)) and _open(use, area, at + Vector2i(0, dy))):
					continue
				var n := _i(next, area)
				var step := def.road_costs[kinds[n]] * (1.0 + BEND * (bend.get_noise_2d(next.x, next.y) + 1.0) * 0.5)
				if dx != 0 and dy != 0:
					step *= 1.41421
				var total := c + step
				if total <= def.lane_reach and total < cost.get(next, INF):
					cost[next] = total
					came[next] = at
					# Steps to the nearest road, as it was before this town's lanes: a guide, not a bound.
					EcsRoadPlanner.heap_push(heap_cost, heap_cell, total + maxi(reach[n], 0) * 0.7, n)
	return []

static func _open(use: PackedByteArray, area: Rect2i, cell: Vector2i) -> bool:
	var u := use[_i(cell, area)]
	return u == Use.FREE or u == Use.ROAD

## Every plot's yard, grown from all footprints at once a ring at a time over free land, to
## `yard_depth` rings; a cell goes to whichever plot reaches it first.
static func _yards(site: EcsSettlementSite, def: EcsSettlementDef, use: PackedByteArray) -> void:
	var area := site.area
	var owner := PackedInt32Array()
	owner.resize(use.size())
	owner.fill(-1)
	var ring: Array[Vector2i] = []
	for k in site.plots.size():
		var rect: Rect2i = site.plots[k]["footprint"]
		site.plots[k]["yard"] = [] as Array[Vector2i]
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				owner[_i(Vector2i(x, y), area)] = k
				ring.append(Vector2i(x, y))
	for depth in def.yard_depth:
		var next_ring: Array[Vector2i] = []
		for at in ring:
			var k := owner[_i(at, area)]
			for side in SIDES:
				var next := at + side
				if not area.has_point(next):
					continue
				var n := _i(next, area)
				if owner[n] == -1 and use[n] == Use.FREE:
					owner[n] = k
					(site.plots[k]["yard"] as Array[Vector2i]).append(next)
					next_ring.append(next)
		ring = next_ring
