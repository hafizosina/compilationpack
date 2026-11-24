class_name WorldSiteCheck
extends RefCounted

## Pure: what is wrong with a town's site and centre, read against its region; empty when sound.
## The area is inside the region and the site on land; the plaza is in the area on no water, the
## well in the plaza; the plaza's land reaches the area's edge; no planned node stands on cleared
## ground.

## `nodes`: planned nodes in whole-region L1 cells, [{cell, size}], to check against the clearing.
static func problems(site: WorldSettlementSite, region_plan: Dictionary, region_def: WorldLandDef,
		def: WorldSettlementDef, rng_seed: int, scale: int, shares: Array, nodes: Array = []) -> Array[String]:
	var out: Array[String] = []
	if site == null:
		return ["no site"]
	if not Rect2i(Vector2i.ZERO, region_def.size * scale).encloses(site.area):
		out.append("the town's area leaves the region")
	if (region_plan["kinds"] as PackedByteArray)[site.l2_cell.y * region_def.size.x + site.l2_cell.x] == WorldTerrainGenerator.WATER:
		out.append("the site is on water")
	if not site.area.encloses(site.plaza):
		out.append("the plaza leaves the town's area")
	if not site.plaza.has_point(site.well):
		out.append("the well isn't in the plaza")
	var terrain := WorldTerrainGenerator.refine_terrain(region_plan, region_def, site.area.size, region_def.child.shore_width,
		site.area.position, scale, rng_seed, 0, shares)
	var kinds := terrain["kinds"] as PackedByteArray
	var w := site.area.size.x
	var h := site.area.size.y
	var land := PackedByteArray()
	land.resize(w * h)
	for i in w * h:
		land[i] = 0 if kinds[i] == WorldTerrainGenerator.WATER else 1
	var plaza := Rect2i(site.plaza.position - site.area.position, site.plaza.size)
	for y in range(plaza.position.y, plaza.end.y):
		for x in range(plaza.position.x, plaza.end.x):
			if land[y * w + x] == 0:
				out.append("water under the plaza at %s" % (site.area.position + Vector2i(x, y)))
				return out
	var found := WorldTerrainGenerator.areas(land, w, h)
	var label := found[0] as PackedInt32Array
	var id := label[plaza.position.y * w + plaza.position.x]
	var edge := false
	for x in w:
		edge = edge or label[x] == id or label[(h - 1) * w + x] == id
	for y in h:
		edge = edge or label[y * w] == id or label[y * w + w - 1] == id
	if not edge:
		out.append("the plaza's land doesn't reach the town's edge")
	for node: Dictionary in nodes:
		var rect := Rect2i(node["cell"], node["size"])
		for cleared in site.cleared:
			if cleared.intersects(rect):
				out.append("a node at %s stands on the town's cleared ground" % node["cell"])
				return out
	return out
