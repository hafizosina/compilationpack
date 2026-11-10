class_name EcsResourceSurvey
extends RefCounted

## Pure: what is within reach of a town, as scores from 0 to 1. Its catchment is every region
## cell a walk of `def.catchment` (by `def.road_costs`) reaches from the site; the site's `costs`
## are used when the road planner has made them. Scores:
##   arable, pasture, forest, rock: shares of the land in reach, scaled so a fair amount scores 1;
##   fish, open_water (lake or sea), sea: from the land in reach that touches water, since a walk
##   barely enters water; river: any of it in reach or on a bank in reach;
##   trade: main roads leaving and water to carry goods;
##   one per deposit key (iron, coal, copper, gold, clay): its cells in reach.
## A fact is present at PRESENT or more.

const PRESENT: float = 0.1
## Deposit cells in reach that score 1.
const DEPOSIT_FULL: float = 24.0

static func of(site: EcsSettlementSite, region_plan: Dictionary, region_def: EcsSettlementDef,
		def: EcsSettlementDef) -> Dictionary[StringName, float]:
	var w := region_def.size.x
	var h := region_def.size.y
	var kinds := region_plan["kinds"] as PackedByteArray
	var river := region_plan["river"] as PackedByteArray
	var cost := site.costs
	if cost.size() != w * h:
		var weights := PackedFloat32Array()
		weights.resize(w * h)
		for i in w * h:
			weights[i] = def.road_costs[kinds[i]]
		cost = EcsRoadPlanner.costs_from(weights, w, h, site.l2_cell)
	var deposits := region_plan.get("deposits", {}) as Dictionary
	var deposit_ids := deposits.get("ids", PackedByteArray()) as PackedByteArray
	var counts := [0, 0, 0, 0, 0]
	var river_cells := 0
	var shore := 0
	var bank := 0
	var found: Dictionary = {}
	var total := 0
	for i in w * h:
		if cost[i] > def.catchment:
			continue
		total += 1
		counts[kinds[i]] += 1
		if river[i] != 0:
			river_cells += 1
		elif kinds[i] != EcsTerrainGenerator.WATER:
			var touches := _touches(kinds, river, w, h, i)
			shore += 1 if touches == 1 else 0
			bank += 1 if touches == 2 else 0
		if not deposit_ids.is_empty() and deposit_ids[i] != 0:
			var key: StringName = deposits["keys"][deposit_ids[i] - 1]
			found[key] = int(found.get(key, 0)) + 1
	var land := maxi(total - counts[EcsTerrainGenerator.WATER], 1)
	var grass := float(counts[EcsTerrainGenerator.GRASS])
	var forest := float(counts[EcsTerrainGenerator.FOREST]) / land
	var open_water := clampf(float(shore) / land / 0.04, 0.0, 1.0)
	var out: Dictionary[StringName, float] = {
		&"arable": clampf((grass + counts[EcsTerrainGenerator.SAND] * 0.5) / land / 0.7, 0.0, 1.0),
		&"pasture": clampf(grass / land / 0.6, 0.0, 1.0) * (1.0 - clampf(forest / 0.5, 0.0, 1.0)),
		&"forest": clampf(forest / 0.5, 0.0, 1.0),
		&"rock": clampf(float(counts[EcsTerrainGenerator.ROCK]) / land / 0.1, 0.0, 1.0),
		&"fish": clampf((shore + bank * 0.5) / land / 0.05, 0.0, 1.0),
		&"river": 1.0 if river_cells > 0 or bank > 0 else 0.0,
		&"open_water": open_water,
		&"sea": open_water if region_plan.get("coast_side", Vector2i.ZERO) != Vector2i.ZERO else 0.0,
	}
	out[&"trade"] = clampf((site.exits.size() - 1) / 3.0, 0.0, 1.0) * 0.7 + 0.3 * maxf(out[&"sea"], out[&"river"])
	for key in (deposits.get("keys", []) as Array):
		out[key] = clampf(found.get(key, 0) / DEPOSIT_FULL, 0.0, 1.0)
	return out

## Whether `facts` holds every key of `all`, one of `any` when it lists some, and none of `absent`.
static func holds(facts: Dictionary, all: Array[StringName], any: Array[StringName],
		absent: Array[StringName] = []) -> bool:
	for key in all:
		if facts.get(key, 0.0) < PRESENT:
			return false
	for key in absent:
		if facts.get(key, 0.0) >= PRESENT:
			return false
	if any.is_empty():
		return true
	for key in any:
		if facts.get(key, 0.0) >= PRESENT:
			return true
	return false

## 1 when land cell `i` touches lake or sea water, 2 when it touches only a river, else 0.
static func _touches(kinds: PackedByteArray, river: PackedByteArray, w: int, h: int, i: int) -> int:
	var x := i % w
	var y := i / w
	var out := 0
	for side in EcsTerrainGenerator.SIDES:
		var nx := x + side.x
		var ny := y + side.y
		if nx < 0 or ny < 0 or nx >= w or ny >= h:
			continue
		var n := ny * w + nx
		if kinds[n] == EcsTerrainGenerator.WATER:
			if river[n] == 0:
				return 1
			out = 2
	return out
