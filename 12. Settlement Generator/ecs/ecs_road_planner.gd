class_name EcsRoadPlanner
extends RefCounted

## Pure and seeded: a town's roads, added to its EcsSettlementSite.
##   1. Exits: the region's edge split into sectors round the site; in each, the edge cell cheapest
##      to reach (one Dijkstra over the region) is an exit. Sectors the sea cuts off are dropped.
##   2. Main roads on L2: routed nearest exit first by A* over ground costs, cells already routed
##      costing `reuse_cost`, so roads share a trunk before forking; smoothed so they curve.
##   3. Main roads on L1: the L2 line scaled, wandering a little, `main_width` wide, from the plaza's
##      edge; a cell on L1 water is a bridge.
##   4. Lanes on L1, inside the town's area: branching off main roads and the plaza, walking a cell
##      at a time, bending, stopping at the edge, water or another road (joining it).
## Road and bridge floors go into the site's commands; road cells and verges into `cleared_cells`.

## Region cells sampled along each sector of the edge.
const EDGE_STEP: int = 4
## How far a refined main road wanders from its L2 line, in L1 cells.
const JITTER: float = 1.5
## A lane joins a road it comes this near; never the road it left before this many cells.
const JOIN_REACH: int = 2
const LEAVE: int = 12
## Lanes shorter than this are dropped.
const MIN_LANE: int = 4
const SIDES: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]

## Lays out `site`'s roads, `area_kinds` being its area's refined ground. False when no exit can
## be reached.
static func plan(site: EcsSettlementSite, region_plan: Dictionary, region_def: EcsSettlementDef,
		def: EcsSettlementDef, area_kinds: PackedByteArray, rng_seed: int, scale: int, catalog: EcsTownCatalog,
		shares: Array) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([rng_seed, site.l2_cell, &"roads"])
	var kinds := region_plan["kinds"] as PackedByteArray
	var w := region_def.size.x
	var h := region_def.size.y
	var weights := PackedFloat32Array()
	weights.resize(w * h)
	for i in w * h:
		weights[i] = def.road_costs[kinds[i]]
	var reach := _dijkstra(weights, w, h, site.l2_cell)
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
	var road_floor := catalog.floor_id(def.road_floor)
	var bridge_floor := catalog.floor_id(def.bridge_floor)
	for cell: Vector2i in main_cells:
		var bridge := water.at(cell)
		site.road_cells[cell] = &"bridge" if bridge else &"main"
	site.bridges = _bridges(site.road_cells)
	_lanes(site, def, area_kinds, rng)
	for cell: Vector2i in site.road_cells:
		var kind: StringName = site.road_cells[cell]
		site.commands.append(EcsBuildCommand.make(EcsBuildCommand.Kind.SET_FLOOR, cell, bridge_floor if kind == &"bridge" else road_floor))
		site.cleared_cells[cell] = true
		if kind != &"lane":
			for dy in range(-def.verge, def.verge + 1):
				for dx in range(-def.verge, def.verge + 1):
					site.cleared_cells[cell + Vector2i(dx, dy)] = true
	return true

## The cheapest cost from `from` to every cell, stepping 8 ways over `weights`.
static func _dijkstra(weights: PackedFloat32Array, w: int, h: int, from: Vector2i) -> PackedFloat32Array:
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
		_pop(heap_cost, heap_cell)
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
					_push(heap_cost, heap_cell, c + step, n)
	return cost

static func _push(costs: PackedFloat32Array, cells: PackedInt32Array, c: float, cell: int) -> void:
	costs.append(c)
	cells.append(cell)
	var k := costs.size() - 1
	while k > 0:
		var parent := (k - 1) / 2
		if costs[parent] <= costs[k]:
			break
		_swap(costs, cells, k, parent)
		k = parent

static func _pop(costs: PackedFloat32Array, cells: PackedInt32Array) -> void:
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

## Lanes inside the town's area: off the main roads every `lane_spacing` cells and off the plaza's
## sides, by chance, each walking and bending until the area's edge, water, its length, or a road
## it joins; one more level off them at half the chance.
static func _lanes(site: EcsSettlementSite, def: EcsSettlementDef, kinds: PackedByteArray, rng: RandomNumberGenerator) -> void:
	var area := site.area
	# Road or plaza per area cell: 0 none, 1 plaza or main road, 2 + n lane n.
	var owner := PackedInt32Array()
	owner.resize(area.size.x * area.size.y)
	for cell: Vector2i in site.road_cells:
		if area.has_point(cell):
			owner[(cell.y - area.position.y) * area.size.x + cell.x - area.position.x] = 1
	for y in range(site.plaza.position.y, site.plaza.end.y):
		for x in range(site.plaza.position.x, site.plaza.end.x):
			owner[(y - area.position.y) * area.size.x + x - area.position.x] = 1
	var starts: Array = []
	for road in site.roads:
		var points := road["points"] as PackedVector2Array
		var next := rng.randi_range(def.lane_spacing.x, def.lane_spacing.y) * 2
		for k in range(1, points.size()):
			if not area.grow(-2).has_point(Vector2i(points[k].round())) or site.plaza.grow(4).has_point(Vector2i(points[k].round())):
				continue
			next -= 1
			if next > 0:
				continue
			next = rng.randi_range(def.lane_spacing.x, def.lane_spacing.y) * 2
			var ahead := (points[k] - points[k - 1]).normalized()
			for side in [-1.0, 1.0]:
				if rng.randf() < def.lane_branch_chance:
					starts.append([points[k], ahead.orthogonal() * side, 1.0])
	for side in SIDES:
		if rng.randf() < def.lane_branch_chance:
			starts.append([Vector2(site.plaza.get_center()), Vector2(side), 1.0])
	var lane := 0
	while not starts.is_empty():
		var start: Array = starts.pop_front()
		lane += 1
		var cells := _walk(start[0], start[1], int(rng.randi_range(def.lane_length.x, def.lane_length.y) * float(start[2])),
			lane + 1, owner, kinds, area, def.lane_turn, rng)
		if cells.size() < MIN_LANE:
			for cell in cells:
				owner[(cell.y - area.position.y) * area.size.x + cell.x - area.position.x] = 0
			continue
		var points := PackedVector2Array()
		for cell in cells:
			points.append(Vector2(cell))
			if not site.road_cells.has(cell):
				site.road_cells[cell] = &"lane"
		site.roads.append({"kind": &"lane", "points": points, "width": def.lane_width})
		if start[2] >= 1.0 and rng.randf() < def.lane_branch_chance * 0.5:
			var from := Vector2(cells[rng.randi_range(0, cells.size() - 1)])
			var along := (Vector2(cells[-1]) - Vector2(cells[0])).normalized()
			starts.append([from, along.orthogonal() * (1.0 if rng.randf() < 0.5 else -1.0), 0.5])

## One lane from `from` heading `heading`, at most `length` cells: 4-connected cells it takes. It
## starts on the road or plaza it leaves and walks out through it, so its first cell touches it.
static func _walk(from: Vector2, heading: Vector2, length: int, id: int, owner: PackedInt32Array,
		kinds: PackedByteArray, area: Rect2i, turn: float, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var at := from
	var last := Vector2i(at.round())
	var aw := area.size.x
	# What it starts on: the road or plaza it leaves, which it may not join straight back into.
	var origin := owner[(last.y - area.position.y) * aw + last.x - area.position.x] if area.has_point(last) else 0
	for step in length:
		heading = heading.rotated(deg_to_rad(rng.randf_range(-turn, turn)))
		at += heading
		var cell := Vector2i(at.round())
		if not area.grow(-1).has_point(cell):
			break
		# A diagonal step takes a side cell too, so the lane stays joined edge to edge.
		var path: Array[Vector2i] = [cell]
		if cell.x != last.x and cell.y != last.y:
			path.push_front(Vector2i(cell.x, last.y))
		for c in path:
			var i := (c.y - area.position.y) * aw + c.x - area.position.x
			if kinds[i] == EcsTerrainGenerator.WATER:
				return cells
			if owner[i] != 0 and owner[i] != id:
				if cells.is_empty():
					# Still leaving the road it starts on.
					continue
				return cells
			owner[i] = id
			cells.append(c)
		last = cell
		var skip := origin if cells.size() < LEAVE else -1
		if cells.size() > 2 and _nearest_road(cell, id, owner, area, skip) != Vector2i(-1, -1):
			# Joins the road it has come near.
			var target := _nearest_road(cell, id, owner, area, skip)
			for c in _straight(cell, target):
				var i := (c.y - area.position.y) * aw + c.x - area.position.x
				if owner[i] != 0 or kinds[i] == EcsTerrainGenerator.WATER:
					break
				owner[i] = id
				cells.append(c)
			return cells
	return cells

## A road cell within JOIN_REACH of `cell`, neither this lane's nor `skip`'s, or (-1, -1).
static func _nearest_road(cell: Vector2i, id: int, owner: PackedInt32Array, area: Rect2i, skip: int) -> Vector2i:
	for r in range(1, JOIN_REACH + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var at := cell + Vector2i(dx, dy)
				if not area.has_point(at):
					continue
				var o := owner[(at.y - area.position.y) * area.size.x + at.x - area.position.x]
				if o != 0 and o != id and o != skip:
					return at
	return Vector2i(-1, -1)

## The 4-connected cells from `a` (excluded) to `b` (excluded), x first.
static func _straight(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var at := a
	while at.x != b.x:
		at.x += signi(b.x - at.x)
		if at != b:
			out.append(at)
	while at.y != b.y:
		at.y += signi(b.y - at.y)
		if at != b:
			out.append(at)
	return out


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
