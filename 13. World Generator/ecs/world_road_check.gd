class_name WorldRoadCheck
extends RefCounted

## Pure: what is wrong with a town's roads; empty when sound. Every main road runs from the site to
## an exit on the region's edge; every road cell is land or a bridge and lanes never bridge; all
## roads are one network joined to the plaza; bridges are few; no planned node stands on a road or
## its verge.

## `nodes`: planned nodes in whole-region L1 cells, [{cell, size}].
static func problems(site: WorldSettlementSite, region_plan: Dictionary, region_def: WorldLandDef,
		def: WorldSettlementDef, rng_seed: int, scale: int, shares: Array, nodes: Array = []) -> Array[String]:
	var out: Array[String] = []
	if site == null:
		return ["no site"]
	var mains := site.roads.filter(func(r: Dictionary) -> bool: return r["kind"] == &"main")
	if mains.is_empty():
		out.append("no main road")
	var w := region_def.size.x
	var h := region_def.size.y
	for road: Dictionary in mains:
		var line := road["l2_points"] as PackedVector2Array
		var end := Vector2i(line[line.size() - 1].round())
		if Vector2i(line[0].round()) != site.l2_cell:
			out.append("a main road doesn't start at the site")
		if end.x != 0 and end.y != 0 and end.x != w - 1 and end.y != h - 1:
			out.append("a main road ends at %s, not the region's edge" % end)
	if site.main_bridges > def.max_bridges:
		out.append("%d bridges on the main roads, more than %d" % [site.main_bridges, def.max_bridges])
	out.append_array(_ground(site, region_plan, region_def, def, rng_seed, scale, shares))
	out.append_array(_network(site))
	for node: Dictionary in nodes:
		var rect := Rect2i(node["cell"], node["size"])
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				if site.cleared_cells.has(Vector2i(x, y)):
					out.append("a node at %s stands on a road or its verge" % node["cell"])
					return out
	return out

## Every road cell is land or a bridge, and lanes never stand on water: read off the L1 ground,
## refined block by block under the roads.
static func _ground(site: WorldSettlementSite, plan: Dictionary, region_def: WorldLandDef, def: WorldSettlementDef,
		rng_seed: int, scale: int, shares: Array) -> Array[String]:
	# Outside the area the ground is refined block by block, only near water.
	var ground := WorldRoadPlanner.WaterAt.new(plan, region_def, rng_seed, scale, shares, site, PackedByteArray())
	var area := WorldTerrainGenerator.refine_terrain(plan, region_def, site.area.size, region_def.child.shore_width, site.area.position,
		scale, rng_seed, 0, shares)["kinds"] as PackedByteArray
	for cell: Vector2i in site.road_cells:
		var water := false
		if site.area.has_point(cell):
			var local := cell - site.area.position
			water = area[local.y * site.area.size.x + local.x] == WorldTerrainGenerator.WATER
		else:
			water = ground.at(cell)
		var kind: StringName = site.road_cells[cell]
		if water and kind != &"bridge":
			return ["a %s cell at %s is on water" % [kind, cell]]
		if not water and kind == &"bridge":
			return ["a bridge cell at %s is on land" % cell]
	return []

## All road cells and the plaza are one 4-connected network.
static func _network(site: WorldSettlementSite) -> Array[String]:
	var open: Dictionary = site.road_cells.duplicate()
	for y in range(site.plaza.position.y, site.plaza.end.y):
		for x in range(site.plaza.position.x, site.plaza.end.x):
			open[Vector2i(x, y)] = true
	var seen: Dictionary = {site.well: true}
	var stack: Array[Vector2i] = [site.well]
	while not stack.is_empty():
		var at: Vector2i = stack.pop_back()
		for side: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			var next := at + side
			if open.has(next) and not seen.has(next):
				seen[next] = true
				stack.append(next)
	var cut := open.size() - seen.size()
	if cut > 0:
		return ["%d road cells aren't joined to the plaza" % cut]
	return []
