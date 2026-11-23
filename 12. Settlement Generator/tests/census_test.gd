extends Node2D

## Headless test for module 12's census (BETTER_TOWNS_PLAN.md §C): a town's people, their work and
## their homes, from what is within its reach.
##
##   "$GODOT" --headless --path . "res://12. Settlement Generator/tests/census_test.tscn"
##
## Exits 0 only if every check passes. Prints what each size of town lives on and holds.

const CATALOG := preload("res://10. Town Generator/defs/town_catalog.tres")
const ENTITIES := preload("res://10. Town Generator/defs/entity_catalog.tres")
const DEFS := "res://12. Settlement Generator/defs/settlements/%s.tres"
const REGION := "res://12. Settlement Generator/defs/lands/region.tres"
const TOWNS: Array[StringName] = [&"hamlet", &"village", &"town"]
const WATERS: Array[int] = [EcsLandDef.Water.RIVER_TO_SEA, EcsLandDef.Water.LAKE, EcsLandDef.Water.COAST]
const SEEDS: int = 4
const ZOOM: int = 8

var _checks: int = 0
var _failures: int = 0
var _plans: Dictionary = {}

func _ready() -> void:
	CATALOG.number()
	var towns := _every_town_is_a_whole_census()
	_busier_towns_have_more_inns(towns)
	_the_same_seed_gives_the_same_town()
	_no_deposits_means_no_mines()
	print("[census] %d/%d checks passed" % [_checks - _failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)

func _region(water: int, deposits: bool = true) -> EcsLandDef:
	var def := (load(REGION) as EcsLandDef).duplicate() as EcsLandDef
	def.water = water
	if not deposits:
		def.deposits = []
	return def

func _pick(region: EcsLandDef, rng_seed: int, town: StringName) -> EcsSettlementSite:
	var key := [region.water, region.deposits.size(), rng_seed]
	if not _plans.has(key):
		var plan := EcsTerrainGenerator.plan(region, rng_seed, CATALOG, ENTITIES)
		_plans[key] = {"plan": plan, "shares": EcsTerrainGenerator.blend_shares(plan, region)}
	var p: Dictionary = _plans[key]
	return EcsSitePicker.pick(p["plan"], region, load(DEFS % town), rng_seed, ZOOM, CATALOG, p["shares"])

## Every size, on three kinds of water over several seeds: the census holds together.
func _every_town_is_a_whole_census() -> Array[EcsSettlementSite]:
	var towns: Array[EcsSettlementSite] = []
	var seen: Dictionary = {}
	for town in TOWNS:
		var def := load(DEFS % town) as EcsSettlementDef
		var first := ""
		var lives: Dictionary = {}
		var usec := 0
		var sums := {"people": 0, "families": 0, "buildings": 0, "homes": 0, "at_work": 0, "labourers": 0, "short": 0}
		var n := 0
		for water in WATERS:
			for s in SEEDS:
				var site := _pick(_region(water), s, town)
				if site == null:
					continue
				towns.append(site)
				n += 1
				var started := Time.get_ticks_usec()
				EcsTownCensus.plan(site.survey, def, s, site.l2_cell)
				usec += Time.get_ticks_usec() - started
				var problem := _problem(site, def)
				if problem != "" and first == "":
					first = "water %d seed %d: %s" % [water, s, problem]
				var economy := site.economy
				lives[economy["character"]] = int(lives.get(economy["character"], 0)) + 1
				seen[economy["character"]] = true
				sums["people"] += economy["population"]
				sums["families"] += (economy["families"] as Array).size()
				sums["labourers"] += economy["labourers"]
				sums["short"] += economy["short_of_workers"]
				for entry: Dictionary in economy["roles"]:
					sums["buildings"] += entry["count"]
					sums["homes"] += entry["count"] if EcsTownCensus.CATALOG.role(entry["role"]).home >= 0 else 0
				for family: Dictionary in economy["families"]:
					sums["at_work"] += 1 if family["home"] == &"work" else 0
		_check("%s: every family housed, every workplace owned, every role allowed, made + imported = needed%s" % [town,
			"" if first == "" else "  " + first], first == "")
		n = maxi(n, 1)
		print("[census]   %s: %s; census %.1f ms a town" % [town, lives, usec / 1000.0 / n])
		print("[census]   %s, a town on average: %d people in %d families; %d buildings, %d of them houses; %d families live at work; %d labourers spare, %d workers short" % [
			town, sums["people"] / n, sums["families"] / n, sums["buildings"] / n, sums["homes"] / n, sums["at_work"] / n,
			sums["labourers"] / n, sums["short"] / n])
	_check("towns differ: %d main trades among them (%s)" % [seen.size(), ", ".join(seen.keys())], seen.size() >= 3)
	return towns

func _problem(site: EcsSettlementSite, def: EcsSettlementDef) -> String:
	var economy := site.economy
	var catalog: EcsEconomyCatalog = EcsTownCensus.CATALOG
	var population: int = economy["population"]
	if population < def.population.x or population > def.population.y:
		return "%d people, outside %s" % [population, def.population]
	var people := 0
	var owners: Dictionary = {}
	var homes_needed: Dictionary = {}
	for family: Dictionary in economy["families"]:
		people += family["people"]
		if family["adults"] < 1:
			return "a family with no adult"
		owners[family["job"]] = int(owners.get(family["job"], 0)) + 1
		var home: StringName = family["home"]
		if home == &"":
			return "a family with no home"
		if home == &"work":
			var job := catalog.role(family["job"])
			if job == null or not job.lives_at_work:
				return "a family living at %s, which has no rooms for it" % family["job"]
			if family["wealth"] == 2:
				return "a rich family living at its workplace"
		else:
			if catalog.role(home).home != family["wealth"] and not (home == EcsTownCensus.HEAD_HOUSE and family["wealth"] == 2):
				return "a family of wealth %d in a %s" % [family["wealth"], home]
			homes_needed[home] = int(homes_needed.get(home, 0)) + 1
	if people != population:
		return "families hold %d of %d people" % [people, population]
	var market := false
	for entry: Dictionary in economy["roles"]:
		var role := catalog.role(entry["role"])
		market = market or role.key == &"market"
		if role.min_tier > def.tier or role.max_tier < def.tier \
				or not EcsResourceSurvey.holds(site.survey, role.requires, role.requires_any, role.absent):
			return "%s built without what it needs" % role.key
		if (entry["wealths"] as Array).size() != entry["count"]:
			return "%s: %d wealths for %d buildings" % [role.key, (entry["wealths"] as Array).size(), entry["count"]]
		if role.places > 0 and role.home < 0 and owners.get(role.key, 0) != entry["count"]:
			return "%d %s, %d owner families" % [entry["count"], role.key, owners.get(role.key, 0)]
		if role.home >= 0 and homes_needed.get(role.key, 0) != entry["count"]:
			return "%d %s for %d families" % [entry["count"], role.key, homes_needed.get(role.key, 0)]
		if role.key == EcsTownCensus.BUFFALO_FARM and (entry["wealths"] as Array).any(func(w: int) -> bool: return w < 1):
			return "a poor farmer with a buffalo"
	if not market:
		return "no market"
	var sells: bool = economy["character"] == &"trading" or economy["character"] == &"port"
	for key: StringName in economy["resources"]:
		var r: Dictionary = economy["resources"][key]
		if r["made"] + r["imported"] < r["need"] - 0.001:
			return "%s short: made %.1f + imported %.1f of %.1f" % [key, r["made"], r["imported"], r["need"]]
		sells = sells or r["exported"] > 0.0
	if not sells:
		return "exports nothing"
	return ""

## Inns follow the travellers: a town with more travellers never asks for fewer inns than one of the
## same size with fewer (those with no family to run them counted), and entertainment needs its
## traffic.
func _busier_towns_have_more_inns(towns: Array[EcsSettlementSite]) -> void:
	var ok := true
	var inns_seen := 0
	var fun_seen := 0
	for town in TOWNS:
		var mine := towns.filter(func(t: EcsSettlementSite) -> bool:
			return t.economy["population"] >= (load(DEFS % town) as EcsSettlementDef).population.x \
				and t.economy["population"] <= (load(DEFS % town) as EcsSettlementDef).population.y)
		mine.sort_custom(func(a: EcsSettlementSite, b: EcsSettlementSite) -> bool:
			return a.economy["traffic"]["travellers"] < b.economy["traffic"]["travellers"])
		var last := 0
		for site: EcsSettlementSite in mine:
			var inns: int = _count(site, &"inn") + int(site.economy["short_of_people"].get(&"inn", 0))
			ok = ok and inns >= last
			last = inns
			inns_seen += inns
			for entry: Dictionary in site.economy["roles"]:
				var role := EcsTownCensus.CATALOG.role(entry["role"])
				if role.group == &"entertainment":
					fun_seen += entry["count"]
					ok = ok and site.economy["traffic"]["level"] >= role.traffic_min
	_check("inns follow travellers, entertainment only where traffic allows (%d inns, %d entertainment in all)" % [inns_seen, fun_seen],
		ok and inns_seen > 0)

func _count(site: EcsSettlementSite, key: StringName) -> int:
	for entry: Dictionary in site.economy["roles"]:
		if entry["role"] == key:
			return entry["count"]
	return 0

func _the_same_seed_gives_the_same_town() -> void:
	var a := _pick(_region(EcsLandDef.Water.RIVER_TO_SEA), 1, &"village")
	var b := _pick(_region(EcsLandDef.Water.RIVER_TO_SEA), 1, &"village")
	_check("the same seed gives the same town", a.economy == b.economy and a.survey == b.survey)

## With no deposits in the region, nothing mines.
func _no_deposits_means_no_mines() -> void:
	var mines := 0
	for s in SEEDS:
		var site := _pick(_region(EcsLandDef.Water.RIVER_TO_SEA, false), s, &"village")
		mines += _count(site, &"iron_mine") + _count(site, &"gold_mine")
	_check("a region with no deposits has no mine (%d seeds)" % SEEDS, mines == 0)

func _check(what: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
	print("[census] %s  %s" % ["ok  " if passed else "FAIL", what])
