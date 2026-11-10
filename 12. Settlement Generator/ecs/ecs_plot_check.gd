class_name EcsPlotCheck
extends RefCounted

## Pure: what is wrong with a town's plots; empty when sound. Every footprint is inside the area, on
## land, off roads, the plaza and other plots; every door is on its footprint's front and has a road
## cell before it; every yard is free land owned once, beside its footprint.

static func problems(site: EcsSettlementSite, region_plan: Dictionary, region_def: EcsLandDef,
		def: EcsSettlementDef, rng_seed: int, scale: int, shares: Array) -> Array[String]:
	if site == null:
		return ["no site"]
	var area := site.area
	var kinds := EcsTerrainGenerator.refine_terrain(region_plan, region_def, area.size, region_def.child.shore_width, area.position,
		scale, rng_seed, 0, shares)["kinds"] as PackedByteArray
	var taken: Dictionary = {}
	for k in site.plots.size():
		var plot := site.plots[k]
		var rect: Rect2i = plot["footprint"]
		if not area.encloses(rect):
			return ["plot %d's footprint %s leaves the town's area" % [k, rect]]
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var why := _taken(site, kinds, taken, Vector2i(x, y))
				if why != "":
					return ["plot %d's footprint is %s at %s" % [k, why, Vector2i(x, y)]]
				taken[Vector2i(x, y)] = k
		var door: Vector2i = plot["door"]
		var front: Vector2i = plot["front"]
		if not rect.has_point(door) or rect.has_point(door + front):
			return ["plot %d's door %s isn't on its front side" % [k, door]]
		if not site.road_cells.has(door + front) and not site.plaza.has_point(door + front):
			return ["plot %d's door %s faces no road" % [k, door]]
	for k in site.plots.size():
		for cell: Vector2i in site.plots[k]["yard"]:
			var why := _taken(site, kinds, taken, cell)
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
static func _taken(site: EcsSettlementSite, kinds: PackedByteArray, taken: Dictionary, cell: Vector2i) -> String:
	var area := site.area
	if not area.has_point(cell):
		return "outside the area"
	if kinds[(cell.y - area.position.y) * area.size.x + cell.x - area.position.x] == EcsTerrainGenerator.WATER:
		return "on water"
	if site.road_cells.has(cell):
		return "on a road"
	if site.plaza.has_point(cell):
		return "on the plaza"
	if taken.has(cell):
		return "on plot %d" % taken[cell]
	return ""
