class_name EcsPlotPlanner
extends RefCounted

## Pure and seeded: a town's plots, each placed by the building it is for, and the lanes they need,
## added to its EcsSettlementSite.
##   0. Quarters: a district point per building group, placed by the groups' likes and dislikes.
##   1. Plots: the census's buildings, highest priority first, each at its role's size where its
##      site rules score best (RULES), plus its group's likes and dislikes of the plots placed
##      before it, a weak pull to its district point, and, for a maker selling from home, the main
##      road and the centre; grid-aligned, a gap apart, facing the side nearest a road. A home
##      seller whose door lands past `sell_reach` sells at the market, which gets a stall for each.
##      The town has no box: a plot stands within the town's radius of the well. A work whose
##      resource isn't in reach goes out to it, in an outlying window joined to the town by a
##      track; anything else that fits nowhere grows the radius (and the ground under it).
##      Whatever still fits nowhere is reported short on the census.
##   2. Lanes: in the area and each window, from the cell before each door to the nearest road,
##      nearest plot first, so lanes merge. A plot no lane reaches is dropped, and reported short.
##   3. Yards: every plot grows from its footprint over free land to its role's yard depth.
## A role with a field or pen (an annex) takes a spot only where it fits beside it, off its front
## and a cell clear of it, so a yard path runs between; annexes block plots, lanes and yards. A
## role with a dock takes a spot only where its pier reaches water, and keeps the pier and the
## walk to it free of later plots; a watermill gets its wheel on the river.
## Footprints, yards, annexes and docks go into `cleared_cells`; floors are left to EcsRoadPlanner.lay.

enum Use { FREE, ROAD, WATER, FOOTPRINT, FIELD }

const SIDES: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
## Site rules a role may weigh, each scored 0–1 at a spot; a deposit key (iron, clay…) is one too.
const RULES: Array[StringName] = [&"plaza", &"centre", &"main_road", &"outskirts", &"water", &"river",
	&"forest", &"rock", &"open", &"apart"]
## Rules that send a work out to its resource when the area has none: these and deposit keys.
const RESOURCE_RULES: Array[StringName] = [&"river", &"water", &"forest", &"rock"]
## Distances, in L1 cells, at which a "near" rule scores 1 and 0.
const NEAR := {&"water": Vector2(3, 8), &"river": Vector2(2, 6), &"forest": Vector2(4, 10), &"rock": Vector2(4, 10),
	&"main_road": Vector2(3, 10), &"deposit": Vector2(4, 10)}
## Distances in L1 cells, door to door, at which a liked or disliked group counts fully and not at all.
const AFFINITY_NEAR := Vector2(8, 80)
## Distance from a door to its group's district point at which the pull is full and gone.
const DISTRICT_NEAR := Vector2(8, 80)
## District point candidates tried per group.
const DISTRICT_TRIES: int = 80
## Weight of the main road and the centre for a maker who sells from home (passing trade).
const SELLER: float = 0.4
## A footprint grows by this for each room its family's list has past two.
const ROOM_GROWTH := Vector2i(3, 2)
## Placement attempts per building.
const TRIES: int = 40
## Cells kept between a footprint and its grid's edge.
const EDGE: int = 3
## How much the lanes' noise adds to a step, so they bend.
const BEND: float = 0.6
## An outlying window's side in L1 cells, how many a work may try, and how far the radius grows a time.
const WINDOW: int = 32
const MAX_WINDOWS: int = 6
const GROW: int = 16
const MAX_GROWS: int = 4
## How far a dock's pier may start from its plot, and how long it runs; how far a wheel's river may be.
const DOCK_REACH: int = 8
const DOCK_LENGTH: int = 6
const WHEEL_REACH: int = 6

## The ground a plot is placed on: the town's area or an outlying window.
class Grid:
	var rect: Rect2i
	var kinds: PackedByteArray
	var river: PackedByteArray
	var deposits: Dictionary
	var use: PackedByteArray
	var reach: PackedInt32Array
	var fields: Dictionary = {}
	## The resource an outlying window was opened for; empty for the area.
	var resource: StringName = &""

	func i(cell: Vector2i) -> int:
		return (cell.y - rect.position.y) * rect.size.x + cell.x - rect.position.x

## What placing needs from the region: {plan, region_def, scale, shares, seed}.
static func plan(site: EcsSettlementSite, def: EcsSettlementDef, terrain: Dictionary, ctx: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([ctx["seed"], site.l2_cell, &"plots"])
	var bounds := Rect2i(Vector2i.ZERO, (ctx["region_def"] as EcsLandDef).size * int(ctx["scale"]))
	var core := grid_of(site, site.area, terrain)
	if _hold_radius(site, bounds):
		core = grid_of(site, site.area, _refine(ctx, site.area))
	var windows: Array[Grid] = []
	var short: Dictionary = {}
	var grows := 0
	var progress: EcsProgress = ctx.get("progress")
	var entries := _entries(site)
	_districts(site, core, entries, rng)
	for n in entries.size():
		var role: EcsSettlementRoleDef = entries[n][0]
		var sells: bool = entries[n][2]
		var rooms: Array = entries[n][3]
		var count := site.plots.size()
		EcsProgress.say(progress, "Placing plots: %s, %d of %d" % [role.display_name, n + 1, entries.size()], 0.56 + 0.14 * n / entries.size())
		var placed := _place_in(site, def, core, role, rng, sells, rooms.size())
		if not placed and _resource_of(role, site.survey) != &"":
			placed = _go_out(site, def, role, windows, core, ctx, rng, sells, rooms.size())
		while not placed and _resource_of(role, site.survey) == &"" and grows < MAX_GROWS:
			grows += 1
			site.radius += GROW
			if _hold_radius(site, bounds):
				core = grid_of(site, site.area, _refine(ctx, site.area))
			placed = _place_in(site, def, core, role, rng, sells, rooms.size())
		if not placed:
			short[role.key] = int(short.get(role.key, 0)) + 1
		elif site.plots.size() > count:
			var plot: Dictionary = site.plots.back()
			plot["wealth"] = entries[n][1]
			if not rooms.is_empty():
				plot["rooms"] = rooms
			if sells:
				var far := Vector2(plot["door"]).distance_to(Vector2(site.well)) > def.sell_reach
				plot["sells"] = &"market" if far else &"home"
			elif role.sells_at_home > 0.0:
				plot["sells"] = &"market"
			var doors: Dictionary = site.quarters["doors"]
			if not doors.has(role.group):
				doors[role.group] = []
			(doors[role.group] as Array).append(plot["door"] + plot["front"])
	var grids: Array[Grid] = [core]
	grids.append_array(windows)
	var dropped: Dictionary = {}
	for g in grids.size():
		EcsProgress.say(progress, "Routing lanes from every door%s" % ("" if g == 0 else ", outlying work %d" % g), 0.7 + 0.15 * g / grids.size())
		var grid := grids[g]
		grid.reach = _reach(grid.use, grid.rect.size)
		_lanes(site, def, grid, ctx["seed"], dropped)
	for k in dropped:
		var key: StringName = site.plots[k]["role"]
		short[key] = int(short.get(key, 0)) + 1
	var kept: Array[Dictionary] = []
	for k in site.plots.size():
		site.plots[k].erase("lane_grid")
		if not dropped.has(k):
			kept.append(site.plots[k])
	site.plots = kept
	var stalls := def.market_stalls
	for plot in site.plots:
		stalls += 1 if plot.get("sells", &"") == &"market" else 0
	for plot in site.plots:
		if plot["role"] == &"market":
			plot["stalls"] = stalls
	EcsProgress.say(progress, "Growing yards", 0.86)
	# Grids can overlap once the town's ground has grown over a window: a cell is one plot's at most.
	var claimed: Dictionary = {}
	for plot in site.plots:
		for cell in EcsBuildRules.cells(plot["footprint"]):
			claimed[cell] = true
		for cell in EcsBuildRules.cells(plot.get("annex", Rect2i())):
			claimed[cell] = true
	for grid in grids:
		# Tracks out to works were routed after a grid was made; yards must not grow over them.
		for cell: Vector2i in site.road_cells:
			if grid.rect.has_point(cell):
				grid.use[grid.i(cell)] = Use.ROAD
		_yards(site, def, grid, claimed)
	for plot in site.plots:
		var role := EcsTownCensus.CATALOG.role(plot["role"])
		var grid := _grid_holding(grids, plot["footprint"])
		if role.annex == &"dock" and not plot.has("dock"):
			var dock := _dock(site, plot, grid)
			if not dock.is_empty():
				plot["dock"] = dock
		if role.key == &"watermill":
			var wheel := _wheel(plot, grid)
			if wheel != Vector2i(-1, -1):
				plot["wheel"] = wheel
	for k in site.plots.size():
		site.plots[k].erase("yard_done")
		var rect: Rect2i = site.plots[k]["footprint"]
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				site.plot_at[Vector2i(x, y)] = k
				site.cleared_cells[Vector2i(x, y)] = true
		for cell: Vector2i in site.plots[k]["yard"]:
			site.plot_at[cell] = k
			site.cleared_cells[cell] = true
		if site.plots[k].has("dock"):
			for cell: Vector2i in site.plots[k]["dock"]["cells"]:
				site.cleared_cells[cell] = true
		var field: Rect2i = site.plots[k].get("annex", Rect2i())
		for y in range(field.position.y, field.end.y):
			for x in range(field.position.x, field.end.x):
				site.plot_at[Vector2i(x, y)] = k
				site.cleared_cells[Vector2i(x, y)] = true
	for window in windows:
		site.outlying.append({"rect": window.rect, "resource": window.resource,
			"terrain": {"kinds": window.kinds, "river": window.river, "deposits": window.deposits}})
	var shortfall: Array[Dictionary] = []
	for key: StringName in short:
		shortfall.append({"role": key, "count": short[key]})
	site.economy["short"] = shortfall
	site.bridges = EcsRoadPlanner.bridges_of(site.road_cells)

## [role def, wealth, sells from home, rooms ([] for its role's)] per building on the census's list, highest priority first.
static func _entries(site: EcsSettlementSite) -> Array[Array]:
	var out: Array[Array] = []
	for entry: Dictionary in site.economy.get("roles", []):
		var role := EcsTownCensus.CATALOG.role(entry["role"])
		var wealths: Array = entry.get("wealths", [])
		var sells: Array = entry.get("sells", [])
		var rooms: Array = entry.get("rooms", [])
		for n in int(entry["count"]):
			out.append([role, wealths[n] if n < wealths.size() else role.wealth, sells[n] if n < sells.size() else false,
				rooms[n] if n < rooms.size() else []])
	out.sort_custom(func(a: Array, b: Array) -> bool:
		var ra: EcsSettlementRoleDef = a[0]
		var rb: EcsSettlementRoleDef = b[0]
		if ra.priority != rb.priority:
			return ra.priority > rb.priority
		return ra.key < rb.key if ra.key != rb.key else a[1] > b[1])
	return out

## Grows the working ground to hold the town's radius (inside `bounds`); whether it grew.
static func _hold_radius(site: EcsSettlementSite, bounds: Rect2i) -> bool:
	var r := ceili(site.radius) + EDGE + 2
	var need := Rect2i(site.well - Vector2i(r, r), Vector2i(r, r) * 2 + Vector2i.ONE).intersection(bounds)
	if site.area.encloses(need):
		return false
	site.area = site.area.merge(need).intersection(bounds)
	return true

## The ground at `rect`: refine_terrain's {kinds, river, deposits} for it.
static func _refine(ctx: Dictionary, rect: Rect2i) -> Dictionary:
	var region := ctx["region_def"] as EcsLandDef
	return EcsTerrainGenerator.refine_terrain(ctx["plan"], region, rect.size, region.child.shore_width, rect.position,
		ctx["scale"], ctx["seed"], 0, ctx["shares"])

## A grid over `rect` of `terrain`, its cells marked water, road (roads and the plaza) or footprint.
static func grid_of(site: EcsSettlementSite, rect: Rect2i, terrain: Dictionary) -> Grid:
	var grid := Grid.new()
	grid.rect = rect
	grid.kinds = terrain["kinds"]
	grid.river = terrain["river"]
	grid.deposits = terrain.get("deposits", {})
	grid.use.resize(rect.size.x * rect.size.y)
	for i in grid.use.size():
		if grid.kinds[i] == EcsTerrainGenerator.WATER:
			grid.use[i] = Use.WATER
	for cell: Vector2i in site.road_cells:
		if rect.has_point(cell):
			grid.use[grid.i(cell)] = Use.ROAD
	var plaza := site.plaza.intersection(rect)
	for y in range(plaza.position.y, plaza.end.y):
		for x in range(plaza.position.x, plaza.end.x):
			grid.use[grid.i(Vector2i(x, y))] = Use.ROAD
	for plot in site.plots:
		var part := (plot["footprint"] as Rect2i).intersection(rect)
		for y in range(part.position.y, part.end.y):
			for x in range(part.position.x, part.end.x):
				grid.use[grid.i(Vector2i(x, y))] = Use.FOOTPRINT
		var field := (plot.get("annex", Rect2i()) as Rect2i).intersection(rect)
		for y in range(field.position.y, field.end.y):
			for x in range(field.position.x, field.end.x):
				grid.use[grid.i(Vector2i(x, y))] = Use.FIELD
		if plot.has("dock"):
			for cell: Vector2i in plot["dock"]["cells"] + plot["dock"]["walk"]:
				if rect.has_point(cell):
					grid.use[grid.i(cell)] = Use.FIELD
	grid.reach = _reach(grid.use, rect.size)
	return grid

## The resource `role` must stand by and goes out for: its first resource `must`, else the
## `must_any` key the survey scores highest; empty when it needs none.
static func _resource_of(role: EcsSettlementRoleDef, survey: Dictionary) -> StringName:
	for rule in role.must:
		if RESOURCE_RULES.has(rule) or not RULES.has(rule):
			return rule
	var best := &""
	for key in role.must_any:
		if survey.get(key, 0.0) >= EcsResourceSurvey.PRESENT and (best == &"" or survey[key] > survey[best]):
			best = key
	return best

## Places one `role` in `grid` at its best-scoring spot of TRIES; false when none fits.
static func _place_in(site: EcsSettlementSite, def: EcsSettlementDef, grid: Grid, role: EcsSettlementRoleDef,
		rng: RandomNumberGenerator, sells: bool = false, rooms: int = 0) -> bool:
	var inner := grid.rect.grow(-EDGE)
	if not inner.has_area():
		return false
	var roadside: Array = []
	for road in site.roads:
		if road["kind"] != &"main":
			continue
		var points := road["points"] as PackedVector2Array
		for k in range(1, points.size(), 4):
			if inner.has_point(Vector2i(points[k].round())):
				roadside.append([points[k], (points[k] - points[k - 1]).normalized().orthogonal()])
	var on_plaza := grid.rect.encloses(site.plaza)
	var best := {}
	var best_score := -INF
	for attempt in TRIES:
		var grow := ROOM_GROWTH * maxi(rooms - 2, 0) if not role.compound else Vector2i.ZERO
		var size := Vector2i(rng.randi_range(role.size_min.x, role.size_max.x), rng.randi_range(role.size_min.y, role.size_max.y)) + grow
		if rng.randf() < 0.5:
			size = Vector2i(size.y, size.x)
		var at := Vector2.ZERO
		var way := rng.randi_range(0, 2)
		var rect := Rect2i()
		if grid.resource != &"":
			at = Vector2(grid.rect.get_center()) + Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4)) * Vector2(grid.rect.size)
		elif way == 0 and on_plaza:
			rect = _by_plaza(site.plaza, size, rng)
		elif way == 1 and not roadside.is_empty():
			var pick: Array = roadside[rng.randi_range(0, roadside.size() - 1)]
			at = (pick[0] as Vector2) + (pick[1] as Vector2) * (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(def.main_width + 2.0, def.main_width + 8.0)
		elif grid.resource == &"":
			at = Vector2(site.well) + Vector2.from_angle(rng.randf() * TAU) * site.radius * sqrt(rng.randf())
		else:
			at = Vector2(rng.randf_range(inner.position.x, inner.end.x), rng.randf_range(inner.position.y, inner.end.y))
		if not rect.has_area():
			rect = Rect2i(Vector2i(at.round()) - size / 2, size)
		if not inner.encloses(rect) or not _fits(rect, grid, def.plot_gap):
			continue
		if grid.resource == &"" and Vector2(rect.get_center()).distance_to(Vector2(site.well)) > site.radius:
			continue
		var noise := rng.randf() * 0.15
		# Every side a door could reach a road from, weighed by the role's rules.
		for front in _fronts(rect, grid):
			if not _musts(site, grid, role, rect, front):
				continue
			var field := Rect2i()
			if role.annex == &"field" or role.annex == &"pen":
				field = _annex_for(rect, front, grid, role, rng)
				if not field.has_area():
					continue
			var dock := {}
			if role.annex == &"dock":
				dock = _dock(site, {"footprint": rect, "front": front}, grid)
				if dock.is_empty():
					continue
			var score := noise
			for rule: StringName in role.sites:
				score += role.sites[rule] * score_rule(site, grid, rule, rect, front)
			var door := _door(rect, front) + front
			score += def.affinity_weight * _affinity(site, role.group, door) + def.district_weight * _district(site, role.group, door)
			if sells:
				score += SELLER * score_rule(site, grid, &"main_road", rect, front) + SELLER * score_rule(site, grid, &"centre", rect, front)
			if score > best_score:
				best_score = score
				best = {"footprint": rect, "front": front, "field": field, "dock": dock}
	if best.is_empty():
		return false
	var rect: Rect2i = best["footprint"]
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			grid.use[grid.i(Vector2i(x, y))] = Use.FOOTPRINT
	var plot := {"role": role.key, "footprint": rect, "front": best["front"], "door": _door(rect, best["front"]), "yard": []}
	var field: Rect2i = best["field"]
	if field.has_area():
		plot["annex"] = field
		plot["annex_kind"] = role.annex
		for y in range(field.position.y, field.end.y):
			for x in range(field.position.x, field.end.x):
				grid.use[grid.i(Vector2i(x, y))] = Use.FIELD
	var dock: Dictionary = best["dock"]
	if not dock.is_empty():
		plot["dock"] = dock
		for cell: Vector2i in dock["cells"] + dock["walk"]:
			grid.use[grid.i(cell)] = Use.FIELD
	site.plots.append(plot)
	return true

## A field or pen for `role` beside `rect` on a side other than its `front`, a cell clear of it:
## the largest of three sizes from the role's range that fits on a side, the sides in random order;
## empty when none fits.
static func _annex_for(rect: Rect2i, front: Vector2i, grid: Grid, role: EcsSettlementRoleDef, rng: RandomNumberGenerator) -> Rect2i:
	var inner := grid.rect.grow(-EDGE)
	var sides: Array[Vector2i] = []
	for side in SIDES:
		if side != front:
			sides.append(side)
	for k in range(sides.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var swap := sides[k]
		sides[k] = sides[j]
		sides[j] = swap
	var shift := rng.randi_range(-2, 2)
	for step in 3:
		var t := step / 2.0
		var size := Vector2i(roundi(lerpf(role.annex_max.x, role.annex_min.x, t)), roundi(lerpf(role.annex_max.y, role.annex_min.y, t)))
		for side in sides:
			# The annex's long side lies along the house.
			var turned := size if side.y != 0 else Vector2i(size.y, size.x)
			var pos := Vector2i.ZERO
			if side.x != 0:
				pos.y = rect.position.y + rect.size.y / 2 - turned.y / 2 + shift
				pos.x = rect.end.x + 1 if side.x > 0 else rect.position.x - 1 - turned.x
			else:
				pos.x = rect.position.x + rect.size.x / 2 - turned.x / 2 + shift
				pos.y = rect.end.y + 1 if side.y > 0 else rect.position.y - 1 - turned.y
			var field := Rect2i(pos, turned)
			if inner.encloses(field) and _field_fits(field, grid):
				return field
	return Rect2i()

## Whether `field` lies on free land a cell clear of every footprint and field.
static func _field_fits(field: Rect2i, grid: Grid) -> bool:
	for y in range(field.position.y, field.end.y):
		for x in range(field.position.x, field.end.x):
			if grid.use[grid.i(Vector2i(x, y))] != Use.FREE:
				return false
	var ring := field.grow(1).intersection(grid.rect)
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, ring.end.x):
			var u := grid.use[grid.i(Vector2i(x, y))]
			if u == Use.FOOTPRINT or u == Use.FIELD:
				return false
	return true

## A `size` footprint flush against a random side of `plaza`, its middle within the plaza's span.
static func _by_plaza(plaza: Rect2i, size: Vector2i, rng: RandomNumberGenerator) -> Rect2i:
	var side := SIDES[rng.randi_range(0, 3)]
	var gap := rng.randi_range(0, 1)
	var pos := Vector2i.ZERO
	if side.x != 0:
		pos.y = plaza.position.y + plaza.size.y / 2 - size.y / 2 + rng.randi_range(-plaza.size.y / 2, plaza.size.y / 2)
		pos.x = plaza.end.x + gap if side.x > 0 else plaza.position.x - gap - size.x
	else:
		pos.x = plaza.position.x + plaza.size.x / 2 - size.x / 2 + rng.randi_range(-plaza.size.x / 2, plaza.size.x / 2)
		pos.y = plaza.end.y + gap if side.y > 0 else plaza.position.y - gap - size.y
	return Rect2i(pos, size)

## Whether `role`'s `must` rules all score 0.5 at `rect`, and one of its `must_any` does.
static func musts_hold(site: EcsSettlementSite, grid: Grid, role: EcsSettlementRoleDef, rect: Rect2i, front: Vector2i) -> bool:
	return _musts(site, grid, role, rect, front)

static func _musts(site: EcsSettlementSite, grid: Grid, role: EcsSettlementRoleDef, rect: Rect2i, front: Vector2i) -> bool:
	for rule in role.must:
		if score_rule(site, grid, rule, rect, front) < 0.5:
			return false
	if role.must_any.is_empty():
		return true
	for rule in role.must_any:
		if score_rule(site, grid, rule, rect, front) >= 0.5:
			return true
	return false

## Rule `rule` scored 0–1 for a footprint `rect` facing `front` in `grid`.
## One point per group the town has, in the catalog's order: each where its group's likes (other
## points, or place rules) score best against its dislikes, kept apart from the points before it.
static func _districts(site: EcsSettlementSite, core: Grid, entries: Array[Array], rng: RandomNumberGenerator) -> void:
	var present: Dictionary = {}
	for entry in entries:
		present[(entry[0] as EcsSettlementRoleDef).group] = true
	var points: Dictionary = {}
	var inner := core.rect.grow(-EDGE)
	for group in EcsTownCensus.CATALOG.groups:
		if not present.has(group.key) or not inner.has_area():
			continue
		var best := Vector2i(-1, -1)
		var best_score := -INF
		for attempt in DISTRICT_TRIES:
			var cell := Vector2i(rng.randi_range(inner.position.x, inner.end.x - 1), rng.randi_range(inner.position.y, inner.end.y - 1))
			if core.use[core.i(cell)] == Use.WATER:
				continue
			var score := rng.randf() * 0.05
			for key in group.likes:
				score += _toward(site, core, points, key, cell)
			for key in group.dislikes:
				score -= _toward(site, core, points, key, cell)
			for other: Vector2i in points.values():
				score -= 0.5 * _falloff(Vector2(cell).distance_to(Vector2(other)), Vector2(4, 16))
			if score > best_score:
				best_score = score
				best = cell
		if best != Vector2i(-1, -1):
			points[group.key] = best
	site.quarters["points"] = points

## How near `cell` is to `key`: another group's point, or a place rule; 0 when there is none yet.
static func _toward(site: EcsSettlementSite, core: Grid, points: Dictionary, key: StringName, cell: Vector2i) -> float:
	if EcsTownCensus.CATALOG.group(key) != null:
		if not points.has(key):
			return 0.0
		return _falloff(Vector2(cell).distance_to(Vector2(points[key])), DISTRICT_NEAR)
	return score_rule(site, core, key, Rect2i(cell, Vector2i.ONE), Vector2i.ZERO)

## A plot of `group` with its door at `door`: +1 for each liked group close by, −1 for each disliked
## one, by the nearest door of that group, averaged over the groups it names.
static func _affinity(site: EcsSettlementSite, group_key: StringName, door: Vector2i) -> float:
	var group := EcsTownCensus.CATALOG.group(group_key)
	if group == null:
		return 0.0
	var doors: Dictionary = site.quarters["doors"]
	var total := 0.0
	var named := 0
	for list in [group.likes, group.dislikes]:
		var sign := 1.0 if list == group.likes else -1.0
		for key: StringName in list:
			if EcsTownCensus.CATALOG.group(key) == null:
				continue
			named += 1
			var nearest := INF
			for other: Vector2i in doors.get(key, []):
				nearest = minf(nearest, Vector2(door).distance_to(Vector2(other)))
			if nearest < INF:
				total += sign * _falloff(nearest, AFFINITY_NEAR)
	return total / maxi(named, 1)

## The pull of `group`'s district point on a door there: 1 at it, 0 far off.
static func _district(site: EcsSettlementSite, group: StringName, door: Vector2i) -> float:
	var points: Dictionary = site.quarters["points"]
	if not points.has(group):
		return 0.0
	return _falloff(Vector2(door).distance_to(Vector2(points[group])), DISTRICT_NEAR)

static func score_rule(site: EcsSettlementSite, grid: Grid, rule: StringName, rect: Rect2i, front: Vector2i) -> float:
	var door := _door(rect, front) + front
	match rule:
		&"plaza":
			return 1.0 if site.plaza.grow(1).has_point(door) else 0.0
		&"centre", &"outskirts":
			var near := 1.0 - clampf(Vector2(rect.get_center()).distance_to(Vector2(site.well)) / maxf(site.radius, 1.0), 0.0, 1.0)
			return near if rule == &"centre" else 1.0 - near
		&"main_road":
			return _falloff(_at(grid, &"main_road", door, site), NEAR[&"main_road"])
		&"open":
			return clampf(minf(_around(grid, &"forest", rect, site), _around(grid, &"rock", rect, site)) / 6.0, 0.0, 1.0)
		&"apart":
			var nearest := 99.0
			for plot in site.plots:
				var other: Rect2i = plot["footprint"]
				var gap := Vector2(maxi(maxi(other.position.x - rect.end.x, rect.position.x - other.end.x), 0),
					maxi(maxi(other.position.y - rect.end.y, rect.position.y - other.end.y), 0))
				nearest = minf(nearest, maxf(gap.x, gap.y))
			return clampf(nearest / 10.0, 0.0, 1.0)
	var span: Vector2 = NEAR.get(rule, NEAR[&"deposit"])
	return _falloff(_around(grid, rule, rect, site), span)

static func _falloff(distance: float, span: Vector2) -> float:
	return clampf((span.y - distance) / (span.y - span.x), 0.0, 1.0)

## The fewest steps from the ring round `rect` to a cell of `key`.
static func _around(grid: Grid, key: StringName, rect: Rect2i, site: EcsSettlementSite) -> float:
	var field := _field(grid, key, site)
	var ring := rect.grow(1).intersection(grid.rect)
	var least := 255
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, ring.end.x):
			if x == ring.position.x or y == ring.position.y or x == ring.end.x - 1 or y == ring.end.y - 1:
				least = mini(least, field[grid.i(Vector2i(x, y))])
	return least

static func _at(grid: Grid, key: StringName, cell: Vector2i, site: EcsSettlementSite) -> float:
	if not grid.rect.has_point(cell):
		return 255.0
	return _field(grid, key, site)[grid.i(cell)]

## Steps from every cell of `grid` to the nearest of `key`'s cells, worked once per grid.
static func _field(grid: Grid, key: StringName, site: EcsSettlementSite) -> PackedByteArray:
	if grid.fields.has(key):
		return grid.fields[key]
	var mask := PackedByteArray()
	mask.resize(grid.kinds.size())
	match key:
		&"water":
			for i in mask.size():
				mask[i] = 1 if grid.kinds[i] == EcsTerrainGenerator.WATER else 0
		&"river":
			for i in mask.size():
				mask[i] = 1 if grid.river[i] != 0 else 0
		&"forest", &"rock":
			var kind := EcsTerrainGenerator.FOREST if key == &"forest" else EcsTerrainGenerator.ROCK
			for i in mask.size():
				mask[i] = 1 if grid.kinds[i] == kind else 0
		&"main_road":
			for cell: Vector2i in site.road_cells:
				if grid.rect.has_point(cell) and site.road_cells[cell] != &"lane":
					mask[grid.i(cell)] = 1
		_:
			var id := (grid.deposits.get("keys", []) as Array).find(key) + 1
			if id > 0:
				var ids := grid.deposits["ids"] as PackedByteArray
				for i in mask.size():
					mask[i] = 1 if ids[i] == id else 0
	var field := EcsTerrainGenerator.distance_from(mask, grid.rect.size.x, grid.rect.size.y, 1, false)
	grid.fields[key] = field
	return field

## Places `role` out at its resource: first in a window already opened for it, then in new windows
## round the catchment's cells of that resource, nearest by route first, each joined by a track.
static func _go_out(site: EcsSettlementSite, def: EcsSettlementDef, role: EcsSettlementRoleDef, windows: Array[Grid],
		core: Grid, ctx: Dictionary, rng: RandomNumberGenerator, sells: bool = false, rooms: int = 0) -> bool:
	var resource := _resource_of(role, site.survey)
	for window in windows:
		if window.resource == resource and _place_in(site, def, window, role, rng, sells, rooms):
			return true
	var region := ctx["region_def"] as EcsLandDef
	var scale: int = ctx["scale"]
	var bounds := Rect2i(Vector2i.ZERO, region.size * scale)
	var tried := 0
	for cell in _resource_cells(site, def, resource, ctx):
		if tried >= MAX_WINDOWS:
			break
		var rect := Rect2i(cell * scale + Vector2i(scale, scale) / 2 - Vector2i(WINDOW, WINDOW) / 2, Vector2i(WINDOW, WINDOW))
		rect.position = rect.position.clamp(Vector2i.ZERO, bounds.end - rect.size)
		if rect.intersects(core.rect.grow(2)) or windows.any(func(w: Grid) -> bool: return rect.intersects(w.rect.grow(2))):
			continue
		tried += 1
		var window := grid_of(site, rect, _refine(ctx, rect))
		window.resource = resource
		var laid := _track(site, def, window, core, windows, ctx)
		if laid.is_empty():
			continue
		window.reach = _reach(window.use, rect.size)
		if _place_in(site, def, window, role, rng, sells, rooms):
			windows.append(window)
			return true
		# Nothing fits: the window and its track go, so no track leads nowhere.
		for undo in laid:
			site.road_cells.erase(undo)
		site.roads.pop_back()
	return false

## The region cells in the catchment holding `resource`, outside the area, nearest by route first.
static func _resource_cells(site: EcsSettlementSite, def: EcsSettlementDef, resource: StringName, ctx: Dictionary) -> Array[Vector2i]:
	var region := ctx["region_def"] as EcsLandDef
	var plan := ctx["plan"] as Dictionary
	var kinds := plan["kinds"] as PackedByteArray
	var river := plan["river"] as PackedByteArray
	var deposits := plan.get("deposits", {}) as Dictionary
	var id := (deposits.get("keys", []) as Array).find(resource) + 1
	var w := region.size.x
	var h := region.size.y
	var core := Rect2i(site.area.position / int(ctx["scale"]), site.area.size / int(ctx["scale"]) + Vector2i.ONE)
	var found: Array[Vector2i] = []
	for i in w * h:
		if site.costs.size() == w * h and site.costs[i] > def.catchment:
			continue
		var cell := Vector2i(i % w, i / w)
		if core.has_point(cell):
			continue
		var kind := kinds[i]
		var hit := false
		match resource:
			&"rock":
				hit = kind == EcsTerrainGenerator.ROCK
			&"forest":
				hit = kind == EcsTerrainGenerator.FOREST and _beside(kinds, w, h, cell, func(k: int, _r: int) -> bool: return k != EcsTerrainGenerator.FOREST)
			&"river":
				hit = kind != EcsTerrainGenerator.WATER and _beside(kinds, w, h, cell, func(_k: int, n: int) -> bool: return river[n] != 0)
			&"water":
				hit = kind != EcsTerrainGenerator.WATER and _beside(kinds, w, h, cell, func(k: int, _r: int) -> bool: return k == EcsTerrainGenerator.WATER)
			_:
				hit = id > 0 and (deposits["ids"] as PackedByteArray)[i] == id
		if hit:
			found.append(cell)
	found.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var ca := site.costs[a.y * w + a.x] if site.costs.size() == w * h else 0.0
		var cb := site.costs[b.y * w + b.x] if site.costs.size() == w * h else 0.0
		return ca < cb if ca != cb else a < b)
	return found

## Whether a 4-neighbour of `cell` passes `test(kind, index)`.
static func _beside(kinds: PackedByteArray, w: int, h: int, cell: Vector2i, test: Callable) -> bool:
	for side in SIDES:
		var n := cell + side
		if n.x >= 0 and n.y >= 0 and n.x < w and n.y < h and test.call(kinds[n.y * w + n.x], n.y * w + n.x):
			return true
	return false

## A track from `window`'s edge nearest the town to the nearest main road outside the area, routed
## on L2 round the area and other windows, drawn 1 cell wide on L1; a cell on water is a bridge.
## Its new cells go into `road_cells` and the window's grid, and are returned; empty when no route
## is found.
static func _track(site: EcsSettlementSite, def: EcsSettlementDef, window: Grid, core: Grid, windows: Array[Grid], ctx: Dictionary) -> Array[Vector2i]:
	var region := ctx["region_def"] as EcsLandDef
	var scale: int = ctx["scale"]
	var head := Vector2i(-1, -1)
	var best := INF
	for y in range(window.rect.position.y, window.rect.end.y):
		for x in range(window.rect.position.x, window.rect.end.x):
			var cell := Vector2i(x, y)
			if x != window.rect.position.x and y != window.rect.position.y and x != window.rect.end.x - 1 and y != window.rect.end.y - 1:
				continue
			if window.use[window.i(cell)] != Use.FREE:
				continue
			var d := Vector2(cell).distance_squared_to(Vector2(site.well))
			if d < best:
				best = d
				head = cell
	if head == Vector2i(-1, -1):
		return []
	var w := region.size.x
	var h := region.size.y
	var kinds := (ctx["plan"] as Dictionary)["kinds"] as PackedByteArray
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, w, h)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for i in w * h:
		astar.set_point_weight_scale(Vector2i(i % w, i / w), def.road_costs[kinds[i]])
	var start := head / scale
	var blocked: Array[Rect2i] = [_l2(core.rect, scale).grow(1)]
	for other in windows:
		blocked.append(_l2(other.rect, scale).grow(1))
	for rect in blocked:
		var part := rect.intersection(astar.region)
		for y in range(part.position.y, part.end.y):
			for x in range(part.position.x, part.end.x):
				astar.set_point_solid(Vector2i(x, y))
	var own := _l2(window.rect, scale)
	for y in range(own.position.y, own.end.y):
		for x in range(own.position.x, own.end.x):
			if Vector2i(x, y) != start and astar.region.has_point(Vector2i(x, y)):
				astar.set_point_solid(Vector2i(x, y))
	astar.set_point_solid(start, false)
	var target := Vector2i(-1, -1)
	var nearest := INF
	for road in site.roads:
		if road["kind"] != &"main":
			continue
		for point: Vector2 in road["l2_points"]:
			var cell := Vector2i(point.round())
			if not astar.region.has_point(cell) or astar.is_point_solid(cell):
				continue
			astar.set_point_weight_scale(cell, def.road_costs[kinds[cell.y * w + cell.x]] * def.reuse_cost)
			var d := Vector2(cell).distance_squared_to(Vector2(start))
			if d < nearest:
				nearest = d
				target = cell
	if target == Vector2i(-1, -1):
		return []
	var path := astar.get_id_path(start, target)
	if path.is_empty():
		return []
	var points := PackedVector2Array([Vector2(head)])
	for k in range(1, path.size()):
		points.append(Vector2(path[k] * scale + Vector2i(scale, scale) / 2))
	var join := _nearest_main(site, path[path.size() - 1] * scale + Vector2i(scale, scale) / 2, scale)
	if join == Vector2i(-1, -1):
		return []
	points.append(Vector2(join))
	var water := EcsRoadPlanner.WaterAt.new(ctx["plan"], region, ctx["seed"], scale, ctx["shares"], site, core.kinds)
	var cells: Array[Vector2i] = []
	for k in range(1, points.size()):
		cells.append_array(_line(Vector2i(points[k - 1]), Vector2i(points[k])))
	var laid: Array[Vector2i] = []
	for cell in cells:
		if site.road_cells.has(cell):
			continue
		laid.append(cell)
		site.road_cells[cell] = &"bridge" if water.at(cell) else &"track"
		if window.rect.has_point(cell):
			window.use[window.i(cell)] = Use.ROAD
	site.roads.append({"kind": &"track", "points": points, "l2_points": PackedVector2Array(Array(path).map(func(c: Vector2i) -> Vector2: return Vector2(c))), "width": 1})
	return laid

static func _l2(rect: Rect2i, scale: int) -> Rect2i:
	var from := rect.position / scale
	return Rect2i(from, (rect.end - Vector2i.ONE) / scale - from + Vector2i.ONE)

## The main road or bridge cell nearest `cell` within a region cell of it, or (-1, -1).
static func _nearest_main(site: EcsSettlementSite, cell: Vector2i, scale: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var nearest := INF
	for dy in range(-scale, scale + 1):
		for dx in range(-scale, scale + 1):
			var at := cell + Vector2i(dx, dy)
			var kind: StringName = site.road_cells.get(at, &"")
			if (kind == &"main" or kind == &"bridge") and Vector2(dx, dy).length_squared() < nearest:
				nearest = Vector2(dx, dy).length_squared()
				best = at
	return best

## The 4-connected cells from `a` to `b`, both included, stepping along the straight line.
static func _line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = [a]
	var steps := maxi(absi(b.x - a.x), absi(b.y - a.y))
	var last := a
	for s in range(1, steps + 1):
		var cell := Vector2i(Vector2(a).lerp(Vector2(b), float(s) / steps).round())
		if cell.x != last.x and cell.y != last.y:
			out.append(Vector2i(cell.x, last.y))
		out.append(cell)
		last = cell
	return out

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

## Whether `rect` stands on free land with land round it and `gap` cells clear of other footprints.
static func _fits(rect: Rect2i, grid: Grid, gap: int) -> bool:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if grid.use[grid.i(Vector2i(x, y))] != Use.FREE:
				return false
	var ring := rect.grow(1).intersection(grid.rect)
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, ring.end.x):
			if grid.use[grid.i(Vector2i(x, y))] == Use.WATER:
				return false
	var room := rect.grow(gap).intersection(grid.rect)
	for y in range(room.position.y, room.end.y):
		for x in range(room.position.x, room.end.x):
			var u := grid.use[grid.i(Vector2i(x, y))]
			if u == Use.FOOTPRINT or u == Use.FIELD:
				return false
	return true

## The sides of `rect` whose door could reach a road, nearest first.
static func _fronts(rect: Rect2i, grid: Grid) -> Array[Vector2i]:
	var found: Array = []
	for side in SIDES:
		var outside := _door(rect, side) + side
		if not grid.rect.has_point(outside):
			continue
		var i := grid.i(outside)
		var steps := 0 if grid.use[i] == Use.ROAD else grid.reach[i]
		if steps >= 0:
			found.append([steps, side])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var out: Array[Vector2i] = []
	for f: Array in found:
		out.append(f[1])
	return out

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

## Lanes for the plots in `grid`, from each door to the nearest road, nearest plot first; a plot
## none reaches goes into `dropped` and its footprint is freed.
static func _lanes(site: EcsSettlementSite, def: EcsSettlementDef, grid: Grid, rng_seed: int, dropped: Dictionary) -> void:
	var bend := FastNoiseLite.new()
	bend.seed = hash([rng_seed, &"lanes"])
	bend.frequency = 0.15
	var order: Array[int] = []
	for k in site.plots.size():
		if grid.rect.encloses(site.plots[k]["footprint"]) and not dropped.has(k) and not _taken(site, k, grid):
			order.append(k)
	order.sort_custom(func(a: int, b: int) -> bool:
		var ra := grid.reach[grid.i(site.plots[a]["door"] + site.plots[a]["front"])]
		var rb := grid.reach[grid.i(site.plots[b]["door"] + site.plots[b]["front"])]
		return ra < rb if ra != rb else a < b)
	for k in order:
		var plot := site.plots[k]
		plot["lane_grid"] = grid.rect
		var start: Vector2i = plot["door"] + plot["front"]
		if grid.use[grid.i(start)] == Use.ROAD:
			continue
		var path := _route(start, grid, def, bend)
		if path.is_empty():
			dropped[k] = true
			var rect: Rect2i = plot["footprint"]
			for y in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					grid.use[grid.i(Vector2i(x, y))] = Use.FREE
			continue
		var points := PackedVector2Array()
		for n in path.size():
			var cell := path[n]
			points.append(Vector2(cell))
			# A diagonal step takes a side cell too, so the lane is joined edge to edge.
			if n > 0 and cell.x != path[n - 1].x and cell.y != path[n - 1].y:
				_take(site, grid, Vector2i(cell.x, path[n - 1].y))
			if n < path.size() - 1:
				_take(site, grid, cell)
		site.roads.append({"kind": &"lane", "points": points, "width": def.lane_width})

## Whether plot `k` was already given its lane in another grid.
static func _taken(site: EcsSettlementSite, k: int, grid: Grid) -> bool:
	return site.plots[k].has("lane_grid") and site.plots[k]["lane_grid"] != grid.rect

static func _take(site: EcsSettlementSite, grid: Grid, cell: Vector2i) -> void:
	grid.use[grid.i(cell)] = Use.ROAD
	if not site.road_cells.has(cell):
		site.road_cells[cell] = &"lane"

## A cheap 8-way route from `start` to a road cell, no dearer than `lane_reach`, over land and round
## footprints, cutting no corner, searched toward the nearest road by the grid's reach; its cells,
## the road cell it meets last. Empty when none.
static func _route(start: Vector2i, grid: Grid, def: EcsSettlementDef, bend: FastNoiseLite) -> Array[Vector2i]:
	var inner := grid.rect.grow(-1)
	var cost: Dictionary = {start: 0.0}
	var came: Dictionary = {}
	var closed: Dictionary = {}
	var heap_cost := PackedFloat32Array([0.0])
	var heap_cell := PackedInt32Array([grid.i(start)])
	while not heap_cost.is_empty():
		var at := Vector2i(heap_cell[0] % grid.rect.size.x, heap_cell[0] / grid.rect.size.x) + grid.rect.position
		EcsRoadPlanner.heap_pop(heap_cost, heap_cell)
		if closed.has(at):
			continue
		closed[at] = true
		var c: float = cost[at]
		if grid.use[grid.i(at)] == Use.ROAD:
			var path: Array[Vector2i] = [at]
			while came.has(path[0]):
				path.push_front(came[path[0]])
			return path
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var next := at + Vector2i(dx, dy)
				# The border is kept clear but for a road on it: a track enters a window there.
				if not grid.rect.has_point(next) or not _open(grid, next):
					continue
				if not inner.has_point(next) and grid.use[grid.i(next)] != Use.ROAD:
					continue
				if dx != 0 and dy != 0 and not (_open(grid, at + Vector2i(dx, 0)) and _open(grid, at + Vector2i(0, dy))):
					continue
				var n := grid.i(next)
				var step := def.road_costs[grid.kinds[n]] * (1.0 + BEND * (bend.get_noise_2d(next.x, next.y) + 1.0) * 0.5)
				if dx != 0 and dy != 0:
					step *= 1.41421
				var total := c + step
				if total <= def.lane_reach and total < cost.get(next, INF):
					cost[next] = total
					came[next] = at
					# Steps to the nearest road, as it was before this grid's lanes: a guide, not a bound.
					EcsRoadPlanner.heap_push(heap_cost, heap_cell, total + maxi(grid.reach[n], 0) * 0.7, n)
	return []

static func _open(grid: Grid, cell: Vector2i) -> bool:
	var u := grid.use[grid.i(cell)]
	return u == Use.FREE or u == Use.ROAD

## The yards of `grid`'s plots, grown from their footprints at once a ring at a time over free
## land, each to its role's yard depth (or the settlement's); a cell goes to whichever reaches it first.
static func _yards(site: EcsSettlementSite, def: EcsSettlementDef, grid: Grid, claimed: Dictionary = {}) -> void:
	var owner := PackedInt32Array()
	owner.resize(grid.use.size())
	owner.fill(-1)
	var ring: Array[Vector2i] = []
	var depth_of: Dictionary = {}
	for k in site.plots.size():
		var rect: Rect2i = site.plots[k]["footprint"]
		if not grid.rect.encloses(rect) or site.plots[k].get("yard_done", false):
			continue
		site.plots[k]["yard_done"] = true
		var role := EcsTownCensus.CATALOG.role(site.plots[k]["role"])
		depth_of[k] = role.yard_depth if role != null and role.yard_depth > 0 else def.yard_depth
		site.plots[k]["yard"] = [] as Array[Vector2i]
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				owner[grid.i(Vector2i(x, y))] = k
				ring.append(Vector2i(x, y))
	var depth := 0
	while not ring.is_empty():
		depth += 1
		var next_ring: Array[Vector2i] = []
		for at in ring:
			var k := owner[grid.i(at)]
			if depth > depth_of[k]:
				continue
			for side in SIDES:
				var next := at + side
				if not grid.rect.has_point(next):
					continue
				var n := grid.i(next)
				if owner[n] == -1 and grid.use[n] == Use.FREE and not claimed.has(next):
					claimed[next] = true
					owner[n] = k
					(site.plots[k]["yard"] as Array[Vector2i]).append(next)
					next_ring.append(next)
		ring = next_ring

static func _grid_holding(grids: Array[Grid], rect: Rect2i) -> Grid:
	for grid in grids:
		if grid.rect.encloses(rect):
			return grid
	return grids[0]

## A pier from the plot out over the water nearest it: the first side (back, then the sides, then
## the front) whose middle reaches water within DOCK_REACH cells over land no footprint or annex
## takes; 2 wide, as long as the water allows up to DOCK_LENGTH. {cells, boat, boat_turns, post},
## or {} when no side reaches water.
static func _dock(site: EcsSettlementSite, plot: Dictionary, grid: Grid) -> Dictionary:
	var rect: Rect2i = plot["footprint"]
	var front: Vector2i = plot["front"]
	var sides: Array[Vector2i] = [-front, Vector2i(front.y, front.x), Vector2i(-front.y, -front.x), front]
	for side in sides:
		var across := Vector2i(absi(side.y), absi(side.x))
		var at := _door(rect, side)
		var shore := Vector2i(-1, -1)
		var walk: Array[Vector2i] = []
		for step in range(1, DOCK_REACH + 1):
			var cell := at + side * step
			if not grid.rect.has_point(cell) or not grid.rect.has_point(cell + across):
				break
			var u := grid.use[grid.i(cell)]
			if u == Use.WATER and grid.use[grid.i(cell + across)] == Use.WATER:
				shore = cell
				break
			if u == Use.FOOTPRINT or u == Use.FIELD:
				break
			walk.append(cell)
		if shore == Vector2i(-1, -1):
			continue
		var cells: Array[Vector2i] = []
		var end := shore
		for step in DOCK_LENGTH:
			var cell := shore + side * step
			if not _water_pair(grid, site, cell, across):
				break
			cells.append_array([cell, cell + across])
			end = cell
		if cells.size() < 4:
			continue
		# Moored past the pier's end, lying along it: a 2x1 boat turned to the pier's run.
		var boat_turns := 0 if side.x != 0 else 1
		var boat := end + side if side.x > 0 or side.y > 0 else end + side * 2
		var boat_cells := [boat, boat + (Vector2i.RIGHT if boat_turns == 0 else Vector2i.DOWN)]
		var boat_ok := boat_cells.all(func(c: Vector2i) -> bool:
			return grid.rect.has_point(c) and grid.use[grid.i(c)] == Use.WATER and not site.road_cells.has(c))
		return {"cells": cells, "walk": walk, "boat": boat if boat_ok else Vector2i(-1, -1), "boat_turns": boat_turns, "post": end + across}
	return {}

static func _water_pair(grid: Grid, site: EcsSettlementSite, cell: Vector2i, across: Vector2i) -> bool:
	for c in [cell, cell + across]:
		if not grid.rect.has_point(c) or grid.use[grid.i(c)] != Use.WATER or site.road_cells.has(c):
			return false
	return true

## The river cell nearest the watermill's footprint within WHEEL_REACH, for its wheel, or (-1, -1).
static func _wheel(plot: Dictionary, grid: Grid) -> Vector2i:
	var rect: Rect2i = plot["footprint"]
	var best := Vector2i(-1, -1)
	var nearest := INF
	var around := rect.grow(WHEEL_REACH).intersection(grid.rect)
	for y in range(around.position.y, around.end.y):
		for x in range(around.position.x, around.end.x):
			var cell := Vector2i(x, y)
			if grid.river[grid.i(cell)] == 0 or grid.use[grid.i(cell)] != Use.WATER:
				continue
			var gap := Vector2(maxi(maxi(rect.position.x - x, x - rect.end.x + 1), 0), maxi(maxi(rect.position.y - y, y - rect.end.y + 1), 0)).length()
			if gap < nearest:
				nearest = gap
				best = cell
	return best
