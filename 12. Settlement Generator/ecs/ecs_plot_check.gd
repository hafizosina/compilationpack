class_name EcsPlotCheck
extends RefCounted

## Pure: what is wrong with a town's plots; empty when sound. Every plot is for a building on the
## role list and stands where that role's `must` rules hold; every footprint is inside the area or
## an outlying window, on land, off roads, the plaza and other plots; every door is on its
## footprint's front and has a road cell before it; every yard is free land owned once, beside its
## footprint.

static func problems(site: EcsSettlementSite, region_plan: Dictionary, region_def: EcsLandDef,
		_def: EcsSettlementDef, rng_seed: int, scale: int, shares: Array) -> Array[String]:
	if site == null:
		return ["no site"]
	var area_terrain := EcsTerrainGenerator.refine_terrain(region_plan, region_def, site.area.size, region_def.child.shore_width,
		site.area.position, scale, rng_seed, 0, shares)
	var grids: Array = [EcsPlotPlanner.grid_of(site, site.area, area_terrain)]
	for window: Dictionary in site.outlying:
		grids.append(EcsPlotPlanner.grid_of(site, window["rect"], window["terrain"]))
	var taken: Dictionary = {}
	for k in site.plots.size():
		var plot := site.plots[k]
		var rect: Rect2i = plot["footprint"]
		var grid: EcsPlotPlanner.Grid = null
		for g: EcsPlotPlanner.Grid in grids:
			if g.rect.encloses(rect):
				grid = g
				break
		if grid == null:
			return ["plot %d's footprint %s is outside the area and every outlying window" % [k, rect]]
		var role := EcsTownEconomy.CATALOG.role(plot.get("role", &""))
		if role == null:
			return ["plot %d is for no building" % k]
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var why := _taken(site, grid, taken, Vector2i(x, y))
				if why != "":
					return ["plot %d's footprint is %s at %s" % [k, why, Vector2i(x, y)]]
				taken[Vector2i(x, y)] = k
		var door: Vector2i = plot["door"]
		var front: Vector2i = plot["front"]
		if not rect.has_point(door) or rect.has_point(door + front):
			return ["plot %d's door %s isn't on its front side" % [k, door]]
		if not site.road_cells.has(door + front) and not site.plaza.has_point(door + front):
			return ["plot %d's door %s faces no road" % [k, door]]
		if not EcsPlotPlanner.musts_hold(site, grid, role, rect, front):
			return ["plot %d, a %s, stands where its rules don't hold" % [k, role.key]]
	for k in site.plots.size():
		for cell: Vector2i in site.plots[k]["yard"]:
			var grid: EcsPlotPlanner.Grid = null
			for g: EcsPlotPlanner.Grid in grids:
				if g.rect.has_point(cell):
					grid = g
					break
			var why := "outside every grid" if grid == null else _taken(site, grid, taken, cell)
			if why != "":
				return ["plot %d's yard is %s at %s" % [k, why, cell]]
			taken[cell] = k
			var beside := false
			for side in EcsPlotPlanner.SIDES:
				beside = beside or taken.get(cell + side, -1) == k
			if not beside:
				return ["plot %d's yard cell %s is cut off from it" % [k, cell]]
	return []

## Why `cell` can't hold a plot, or "" when it can.
static func _taken(site: EcsSettlementSite, grid: EcsPlotPlanner.Grid, taken: Dictionary, cell: Vector2i) -> String:
	if grid.kinds[grid.i(cell)] == EcsTerrainGenerator.WATER:
		return "on water"
	if site.road_cells.has(cell):
		return "on a road"
	if site.plaza.has_point(cell):
		return "on the plaza"
	if taken.has(cell):
		return "on plot %d" % taken[cell]
	return ""
