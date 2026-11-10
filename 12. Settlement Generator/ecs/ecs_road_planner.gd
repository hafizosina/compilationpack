class_name EcsRoadPlanner
extends RefCounted

## Pure and seeded: a town's roads, added to its EcsSettlementSite.
##   1. Exits: the region's edge split into sectors round the site; in each, the edge cell cheapest
##      to reach (one Dijkstra over the region) is an exit. Sectors the sea cuts off are dropped.
##   2. Main roads on L2: routed nearest exit first by A* over ground costs, cells already routed
##      costing `reuse_cost`, so roads share a trunk before forking; smoothed so they curve.
##   3. Main roads on L1: the L2 line scaled, wandering a little, `main_width` wide, from the plaza's
##      edge; a cell on L1 water is a bridge.
## Lanes come from the plots (EcsPlotPlanner). `lay` then puts every road's floor into the site's
## commands, and road cells and verges into `cleared_cells`.

## Region cells sampled along each sector of the edge.
const EDGE_STEP: int = 4
## How far a refined main road wanders from its L2 line, in L1 cells.
const JITTER: float = 1.5

## Lays out `site`'s main roads, `area_kinds` being its area's refined ground. False when no exit
## can be reached.
static func plan(site: EcsSettlementSite, region_plan: Dictionary, region_def: EcsSettlementDef,
		def: EcsSettlementDef, area_kinds: PackedByteArray, rng_seed: int, scale: int, shares: Array) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([rng_seed, site.l2_cell, &"roads"])
	var kinds := region_plan["kinds"] as PackedByteArray
	var w := region_def.size.x
	var h := region_def.size.y
	var weights := PackedFloat32Array()
	weights.resize(w * h)
	for i in w * h:
		weights[i] = def.road_costs[kinds[i]]
	var reach := costs_from(weights, w, h, site.l2_cell)
	site.costs = reach
	var exits := _exits(reach, kinds, w, h, site.l2_cell, rng.randi_range(def.exits.x, def.exits.y), rng.randf() * TAU)
	if exits.is_empty():
		return false
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, w, h)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for i in w * h:
		astar.set_point_weight_scale(Vector2i(i % w, i / w), weights[i])
	var mains: Array[PackedVector2Array] = []
	for exit in exits:
		var path := astar.get_id_path(site.l2_cell, exit)
		if path.is_empty():
			continue
		var line := PackedVector2Array()
		for cell in path:
			line.append(Vector2(cell))
			astar.set_point_weight_scale(cell, weights[cell.y * w + cell.x] * def.reuse_cost)
		mains.append(_smooth(line, 2))
		site.exits.append(exit)
	if mains.is_empty():
		return false
	var water := WaterAt.new(region_plan, region_def, def, rng_seed, scale, shares, site, area_kinds)
	var jitter := FastNoiseLite.new()
	jitter.seed = hash([rng_seed, 8])
	jitter.frequency = 0.05
	var main_cells: Dictionary = {}
	var bounds := Rect2i(Vector2i.ZERO, region_def.size * scale)
	for line in mains:
		var points := _draw_main(line, scale, def.main_width, jitter, site, bounds, main_cells)
		site.roads.append({"kind": &"main", "points": points, "l2_points": line, "width": def.main_width})
	for cell: Vector2i in main_cells:
		var bridge := water.at(cell)
		site.road_cells[cell] = &"bridge" if bridge else &"main"
	site.bridges = _bridges(site.road_cells)
	return true

## Every road cell of `site` floored in its commands (road, or wood for a bridge) and cleared, with
## a `verge` round main roads and bridges.
static func lay(site: EcsSettlementSite, def: EcsSettlementDef, catalog: EcsTownCatalog) -> void:
	var road_floor := catalog.floor_id(def.road_floor)
	var bridge_floor := catalog.floor_id(def.bridge_floor)
	for cell: Vector2i in site.road_cells:
		var kind: StringName = site.road_cells[cell]
		site.commands.append(EcsBuildCommand.make(EcsBuildCommand.Kind.SET_FLOOR, cell, bridge_floor if kind == &"bridge" else road_floor))
		site.cleared_cells[cell] = true
		if kind != &"lane":
			for dy in range(-def.verge, def.verge + 1):
				for dx in range(-def.verge, def.verge + 1):
					site.cleared_cells[cell + Vector2i(dx, dy)] = true

## The cheapest cost from `from` to every cell, stepping 8 ways over `weights`.
static func costs_from(weights: PackedFloat32Array, w: int, h: int, from: Vector2i) -> PackedFloat32Array:
	var cost := PackedFloat32Array()
	cost.resize(w * h)
	cost.fill(INF)
	var start := from.y * w + from.x
	cost[start] = 0.0
	var heap_cost := PackedFloat32Array([0.0])
	var heap_cell := PackedInt32Array([start])
	while not heap_cost.is_empty():
		var c := heap_cost[0]
		var i := heap_cell[0]
		heap_pop(heap_cost, heap_cell)
		if c > cost[i]:
			continue
		var x := i % w
		var y := i / w
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var nx := x + dx
				var ny := y + dy
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var n := ny * w + nx
				var step := weights[n] * (1.41421 if dx != 0 and dy != 0 else 1.0)
				if c + step < cost[n]:
					cost[n] = c + step
					heap_push(heap_cost, heap_cell, c + step, n)
	return cost

## Binary heap of cells by cost, in two parallel arrays: adds one.
static func heap_push(costs: PackedFloat32Array, cells: PackedInt32Array, c: float, cell: int) -> void:
	costs.append(c)
	cells.append(cell)
	var k := costs.size() - 1
	while k > 0:
		var parent := (k - 1) / 2
		if costs[parent] <= costs[k]:
			break
		_swap(costs, cells, k, parent)
		k = parent

## Removes the cheapest.
static func heap_pop(costs: PackedFloat32Array, cells: PackedInt32Array) -> void:
	var last := costs.size() - 1
	costs[0] = costs[last]
	cells[0] = cells[last]
	costs.resize(last)
	cells.resize(last)
	var k := 0
	while true:
		var left := k * 2 + 1
		var right := left + 1
		var least := k
		if left < last and costs[left] < costs[least]:
			least = left
		if right < last and costs[right] < costs[least]:
			least = right
		if least == k:
			break
		_swap(costs, cells, k, least)
		k = least

static func _swap(costs: PackedFloat32Array, cells: PackedInt32Array, a: int, b: int) -> void:
	var c := costs[a]
	costs[a] = costs[b]
	costs[b] = c
	var i := cells[a]
	cells[a] = cells[b]
	cells[b] = i

## One exit per sector of the region's edge round `site` (`count` sectors from angle `turn`): its
## cheapest land edge cell; nearest first. Sectors with no reachable land edge are dropped.
static func _exits(reach: PackedFloat32Array, kinds: PackedByteArray, w: int, h: int, site: Vector2i,
		count: int, turn: float) -> Array[Vector2i]:
	var best: Array = []
	for k in count:
		best.append([INF, Vector2i(-1, -1)])
	var edge: Array[Vector2i] = []
	for x in range(0, w, EDGE_STEP):
		edge.append_array([Vector2i(x, 0), Vector2i(x, h - 1)])
	for y in range(0, h, EDGE_STEP):
		edge.append_array([Vector2i(0, y), Vector2i(w - 1, y)])
	for cell in edge:
		var i := cell.y * w + cell.x
		if kinds[i] == EcsTerrainGenerator.WATER or reach[i] == INF:
			continue
		var angle := fposmod(Vector2(cell - site).angle() - turn, TAU)
		var sector := mini(int(angle / TAU * count), count - 1)
		if reach[i] < best[sector][0]:
			best[sector] = [reach[i], cell]
	best = best.filter(func(b: Array) -> bool: return b[0] != INF)
	best.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var out: Array[Vector2i] = []
	for b: Array in best:
		out.append(b[1])
	return out

## `line` with `rounds` of Chaikin's corner cutting, its ends kept.
static func _smooth(line: PackedVector2Array, rounds: int) -> PackedVector2Array:
	for r in rounds:
		if line.size() < 3:
			return line
		var out := PackedVector2Array([line[0]])
		for k in line.size() - 1:
			out.append(line[k].lerp(line[k + 1], 0.25))
			out.append(line[k].lerp(line[k + 1], 0.75))
		out.append(line[line.size() - 1])
		line = out
	return line

## A main road's L2 line drawn into L1 cells `width` wide, wandering a little, leaving out the plaza;
## its L1 points.
static func _draw_main(line: PackedVector2Array, scale: int, width: int, jitter: FastNoiseLite,
		site: EcsSettlementSite, bounds: Rect2i, cells: Dictionary) -> PackedVector2Array:
	var points := PackedVector2Array()
	for k in range(1, line.size()):
		var a := (line[k - 1] + Vector2(0.5, 0.5)) * scale - Vector2(0.5, 0.5)
		var b := (line[k] + Vector2(0.5, 0.5)) * scale - Vector2(0.5, 0.5)
		var steps := maxi(ceili(a.distance_to(b) * 2.0), 1)
		for s in steps:
			var at := a.lerp(b, float(s) / steps)
			at += Vector2(jitter.get_noise_2d(at.x, at.y), jitter.get_noise_2d(at.y, at.x)) * JITTER
			points.append(at)
			_brush(at, width, cells, site.plaza, bounds)
	return points

## The `width`-square of cells round `at`, inside `bounds` and outside `skip`.
static func _brush(at: Vector2, width: int, cells: Dictionary, skip: Rect2i, bounds: Rect2i) -> void:
	var corner := Vector2i(floori(at.x - width * 0.5 + 0.5), floori(at.y - width * 0.5 + 0.5))
	for dy in width:
		for dx in width:
			var cell := corner + Vector2i(dx, dy)
			if bounds.has_point(cell) and not skip.has_point(cell):
				cells[cell] = true

## Water crossings: groups of 8-touching bridge cells.
static func _bridges(road_cells: Dictionary) -> int:
	var seen: Dictionary = {}
	var count := 0
	for cell: Vector2i in road_cells:
		if road_cells[cell] != &"bridge" or seen.has(cell):
			continue
		count += 1
		var stack: Array[Vector2i] = [cell]
		seen[cell] = true
		while not stack.is_empty():
			var at: Vector2i = stack.pop_back()
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var next := at + Vector2i(dx, dy)
					if road_cells.get(next, &"") == &"bridge" and not seen.has(next):
						seen[next] = true
						stack.append(next)
	return count


## Whether an L1 cell is water, refining only the 8×8 blocks near water: a cell whose region cell
## and its neighbours are all land is land at L1 too (EcsTerrainCheck.follows holds it to that).
class WaterAt:
	var _plan: Dictionary
	var _region: EcsSettlementDef
	var _def: EcsSettlementDef
	var _seed: int
	var _scale: int
	var _shares: Array
	var _site: EcsSettlementSite
	var _area_kinds: PackedByteArray
	var _blocks: Dictionary = {}

	func _init(plan: Dictionary, region: EcsSettlementDef, def: EcsSettlementDef, rng_seed: int, scale: int,
			shares: Array, site: EcsSettlementSite, area_kinds: PackedByteArray) -> void:
		_plan = plan
		_region = region
		_def = def
		_seed = rng_seed
		_scale = scale
		_shares = shares
		_site = site
		_area_kinds = area_kinds

	func at(cell: Vector2i) -> bool:
		if _site.area.has_point(cell):
			var local := cell - _site.area.position
			return _area_kinds[local.y * _site.area.size.x + local.x] == EcsTerrainGenerator.WATER
		var parent := Vector2i((Vector2(cell) / _scale).floor())
		var kinds := _plan["kinds"] as PackedByteArray
		var near_water := false
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var p := (parent + Vector2i(dx, dy)).clamp(Vector2i.ZERO, _region.size - Vector2i.ONE)
				near_water = near_water or kinds[p.y * _region.size.x + p.x] == EcsTerrainGenerator.WATER
		if not near_water:
			return false
		if not _blocks.has(parent):
			_blocks[parent] = EcsTerrainGenerator.refine_terrain(_plan, _region, Vector2i(_scale, _scale), _def.shore_width,
				parent * _scale, _scale, _seed, 0, _shares)["kinds"]
		var local := cell - parent * _scale
		return (_blocks[parent] as PackedByteArray)[local.y * _scale + local.x] == EcsTerrainGenerator.WATER
