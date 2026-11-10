class_name EcsSitePicker
extends RefCounted

## Pure and seeded: where a region's town goes, its centre and its roads. `pick` scores every region
## cell and takes the best whose centre and roads work out; `place` puts the town at a chosen cell.
## Either way the centre is laid out on L1 cells (a stone plaza with the well) from the same terrain
## the chunks draw, so the town lands on the ground it was planned on; EcsRoadPlanner adds the roads.

## Best-scored sites tried, in order, before giving up.
const TRIES: int = 20
## A town's area must be at least this share land.
const MIN_ROOM: float = 0.7
## Added to a site whose water is a river within reach: mills and docks want one.
const RIVER_BONUS: float = 0.2

## The town for `def` on the region, or null when no site works.
static func pick(region_plan: Dictionary, region_def: EcsSettlementDef, def: EcsSettlementDef, rng_seed: int,
		scale: int, catalog: EcsTownCatalog, shares: Array) -> EcsSettlementSite:
	var maps := _maps(region_plan, region_def, def, scale)
	var scored: Array = []
	for i in region_def.size.x * region_def.size.y:
		var parts := _score(maps, Vector2i(i % region_def.size.x, i / region_def.size.x), region_def, def)
		if not parts.has("refused"):
			scored.append(parts)
	var middle := Vector2(region_def.size) * 0.5
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["total"] != b["total"]:
			return a["total"] > b["total"]
		var da := Vector2(a["cell"] as Vector2i).distance_squared_to(middle)
		var db := Vector2(b["cell"] as Vector2i).distance_squared_to(middle)
		if da != db:
			return da < db
		return (a["cell"] as Vector2i) < (b["cell"] as Vector2i))
	for k in mini(scored.size(), TRIES):
		var site := _centre(scored[k], region_plan, region_def, def, rng_seed, scale, catalog, shares)
		if site != null:
			return site
	return null

## The town for `def` at region cell `cell`: {site} or {refused: why}.
static func place(region_plan: Dictionary, region_def: EcsSettlementDef, def: EcsSettlementDef, cell: Vector2i,
		rng_seed: int, scale: int, catalog: EcsTownCatalog, shares: Array) -> Dictionary:
	if not Rect2i(Vector2i.ZERO, region_def.size).has_point(cell):
		return {"refused": "outside the region"}
	var parts := _score(_maps(region_plan, region_def, def, scale), cell, region_def, def)
	if parts.has("refused"):
		return parts
	var site := _centre(parts, region_plan, region_def, def, rng_seed, scale, catalog, shares)
	if site == null:
		return {"refused": "no room for the plaza there"}
	return {"site": site}

## The town's area in region cells for a site at `cell`.
static func area_cells(cell: Vector2i, def: EcsSettlementDef, scale: int) -> Rect2i:
	var size := Vector2i(ceili(def.size.x / float(scale)), ceili(def.size.y / float(scale)))
	return Rect2i(cell - size / 2, size)

## What every site's score reads: distances to water and river, running sums of open land and of
## land, and which land areas reach the region's edge.
static func _maps(plan: Dictionary, region_def: EcsSettlementDef, def: EcsSettlementDef, scale: int) -> Dictionary:
	var w := region_def.size.x
	var h := region_def.size.y
	var kinds := plan["kinds"] as PackedByteArray
	var river := plan["river"] as PackedByteArray
	var open := PackedFloat32Array()
	var land := PackedFloat32Array()
	var land_mask := PackedByteArray()
	open.resize(w * h)
	land.resize(w * h)
	land_mask.resize(w * h)
	for i in w * h:
		match kinds[i]:
			EcsTerrainGenerator.GRASS, EcsTerrainGenerator.SAND:
				open[i] = 1.0
			EcsTerrainGenerator.FOREST, EcsTerrainGenerator.ROCK:
				open[i] = 0.5
		var is_land := kinds[i] != EcsTerrainGenerator.WATER
		land[i] = 1.0 if is_land else 0.0
		land_mask[i] = 1 if is_land else 0
	var found := EcsTerrainGenerator.areas(land_mask, w, h)
	var label := found[0] as PackedInt32Array
	var reaches: Dictionary = {}
	for x in w:
		reaches[label[x]] = true
		reaches[label[(h - 1) * w + x]] = true
	for y in h:
		reaches[label[y * w]] = true
		reaches[label[y * w + w - 1]] = true
	var window := maxi(3, ceili(def.plaza_size.x / float(scale)) + 2)
	return {
		"water": EcsTerrainGenerator.distance_from(kinds, w, h, EcsTerrainGenerator.WATER, false),
		"river": EcsTerrainGenerator.distance_from(river, w, h, 1, false),
		"open": _running_sum(open, w, h), "land": _running_sum(land, w, h),
		"label": label, "reaches": reaches, "window": window | 1, "area": area_cells(Vector2i.ZERO, def, scale).size,
	}

## A site at `cell`: {cell, water, open, room, river, total} or {refused: why}.
static func _score(maps: Dictionary, cell: Vector2i, region_def: EcsSettlementDef, def: EcsSettlementDef) -> Dictionary:
	var w := region_def.size.x
	var i := cell.y * w + cell.x
	if (maps["water"] as PackedByteArray)[i] == 0:
		return {"refused": "on water"}
	var area := Rect2i(cell - (maps["area"] as Vector2i) / 2, maps["area"])
	var inside := Rect2i(Vector2i.ZERO, region_def.size).grow(-def.edge_margin_cells)
	if not inside.encloses(area):
		return {"refused": "too near the region's edge for a town this size"}
	var room := _sum(maps["land"], w, area) / float(area.get_area())
	if room < MIN_ROOM:
		return {"refused": "too much water under the town (%.0f%% land)" % (room * 100.0)}
	if not (maps["reaches"] as Dictionary).has((maps["label"] as PackedInt32Array)[i]):
		return {"refused": "its land doesn't reach the region's edge"}
	var near := def.water_near
	var distance: int = (maps["water"] as PackedByteArray)[i]
	var water := 1.0
	if distance < near.x:
		water = float(distance) / near.x
	elif distance > near.y:
		water = maxf(0.0, 1.0 - float(distance - near.y) / near.y)
	var k: int = maps["window"]
	var open := _sum(maps["open"], w, Rect2i(cell - Vector2i(k / 2, k / 2), Vector2i(k, k)).intersection(Rect2i(Vector2i.ZERO, region_def.size))) / float(k * k)
	var river := RIVER_BONUS if (maps["river"] as PackedByteArray)[i] <= near.y else 0.0
	return {"cell": cell, "water": water, "open": open, "room": room, "river": river,
		"total": def.water_weight * water + def.open_weight * open + room + river}

## Lays out the centre of a town scored by `parts`: its L1 area, refined from the region, and the
## plaza with the fewest forest and rock cells near the site, on no water, whose land reaches the
## area's edge. Null when there is none.
static func _centre(parts: Dictionary, plan: Dictionary, region_def: EcsSettlementDef, def: EcsSettlementDef,
		rng_seed: int, scale: int, catalog: EcsTownCatalog, shares: Array) -> EcsSettlementSite:
	var cell: Vector2i = parts["cell"]
	var mid := cell * scale + Vector2i(scale / 2, scale / 2)
	var origin := (mid - def.size / 2).clamp(Vector2i.ZERO, region_def.size * scale - def.size)
	var terrain := EcsTerrainGenerator.refine_terrain(plan, region_def, def.size, def.shore_width, origin, scale, rng_seed, 0, shares)
	var kinds := terrain["kinds"] as PackedByteArray
	var w := def.size.x
	var h := def.size.y
	var water := PackedFloat32Array()
	var rough := PackedFloat32Array()
	var land_mask := PackedByteArray()
	water.resize(w * h)
	rough.resize(w * h)
	land_mask.resize(w * h)
	for i in w * h:
		var kind := kinds[i]
		water[i] = 1.0 if kind == EcsTerrainGenerator.WATER else 0.0
		rough[i] = 1.0 if kind == EcsTerrainGenerator.FOREST or kind == EcsTerrainGenerator.ROCK else 0.0
		land_mask[i] = 0 if kind == EcsTerrainGenerator.WATER else 1
	var water_sum := _running_sum(water, w, h)
	var rough_sum := _running_sum(rough, w, h)
	var centre := mid - origin
	var reach := mini(w, h) / 4
	var plaza := Rect2i()
	var best := INF
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var rect := Rect2i(centre + Vector2i(dx, dy) - def.plaza_size / 2, def.plaza_size)
			if rect.position.x < 1 or rect.position.y < 1 or rect.end.x > w - 1 or rect.end.y > h - 1:
				continue
			if _sum(water_sum, w, rect) > 0.0:
				continue
			var cost := _sum(rough_sum, w, rect) + Vector2(dx, dy).length() * 0.01
			if cost < best:
				best = cost
				plaza = rect
	if best == INF:
		return null
	var found := EcsTerrainGenerator.areas(land_mask, w, h)
	var label := (found[0] as PackedInt32Array)[plaza.position.y * w + plaza.position.x]
	if not _touches_edge(found[0], w, h, label):
		return null
	var site := EcsSettlementSite.new()
	site.l2_cell = cell
	site.area = Rect2i(origin, def.size)
	site.plaza = Rect2i(origin + plaza.position, plaza.size)
	site.well = site.plaza.position + site.plaza.size / 2
	var floor_id := catalog.floor_id(def.plaza_floor)
	for y in range(site.plaza.position.y, site.plaza.end.y):
		for x in range(site.plaza.position.x, site.plaza.end.x):
			site.commands.append(EcsBuildCommand.make(EcsBuildCommand.Kind.SET_FLOOR, Vector2i(x, y), floor_id))
	site.commands.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, site.well, def.well, 0))
	site.cleared.append(site.plaza.grow(def.clear_margin))
	site.score = parts
	if not EcsRoadPlanner.plan(site, plan, region_def, def, kinds, rng_seed, scale, catalog, shares):
		return null
	return site

static func _touches_edge(label: PackedInt32Array, w: int, h: int, id: int) -> bool:
	for x in w:
		if label[x] == id or label[(h - 1) * w + x] == id:
			return true
	for y in h:
		if label[y * w] == id or label[y * w + w - 1] == id:
			return true
	return false

## A summed-area table of `values` (`w` × `h`), one row and column larger.
static func _running_sum(values: PackedFloat32Array, w: int, h: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize((w + 1) * (h + 1))
	for y in h:
		var row := 0.0
		for x in w:
			row += values[y * w + x]
			out[(y + 1) * (w + 1) + x + 1] = out[y * (w + 1) + x + 1] + row
	return out

## The sum of the values over `rect`, read off a running sum of a `w`-wide grid.
static func _sum(table: PackedFloat32Array, w: int, rect: Rect2i) -> float:
	var stride := w + 1
	var a := rect.position
	var b := rect.end
	return table[b.y * stride + b.x] - table[a.y * stride + b.x] - table[b.y * stride + a.x] + table[a.y * stride + a.x]
