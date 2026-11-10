extends Node2D

## Headless test for module 12's step 5: what a town is, from what is within its reach.
##
##   "$GODOT" --headless --path . "res://12. Settlement Generator/tests/economy_test.tscn"
##
## Exits 0 only if every check passes. Prints what each town lives on.

const CATALOG := preload("res://10. Town Generator/defs/town_catalog.tres")
const ENTITIES := preload("res://10. Town Generator/defs/entity_catalog.tres")
const DEFS := "res://12. Settlement Generator/defs/settlements/%s.tres"
const TOWNS: Array[StringName] = [&"hamlet", &"village", &"town"]
const WATERS: Array[int] = [EcsSettlementDef.Water.RIVER_TO_SEA, EcsSettlementDef.Water.LAKE, EcsSettlementDef.Water.COAST]
const SEEDS: int = 4
const ZOOM: int = 8

var _checks: int = 0
var _failures: int = 0
var _plans: Dictionary = {}

func _ready() -> void:
	CATALOG.number()
	var towns := _every_town_lives_on_what_it_has()
	_side_lines_build_their_small_set(towns)
	_the_same_seed_gives_the_same_town()
	_no_deposits_means_no_mining()
	print("[economy] %d/%d checks passed" % [_checks - _failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)

func _region(water: int, deposits: bool = true) -> EcsSettlementDef:
	var def := (load(DEFS % &"region") as EcsSettlementDef).duplicate() as EcsSettlementDef
	def.water = water
	if not deposits:
		def.deposits = []
	return def

func _pick(region: EcsSettlementDef, rng_seed: int, town: StringName) -> EcsSettlementSite:
	var key := [region.water, region.deposits.size(), rng_seed]
	if not _plans.has(key):
		var plan := EcsTerrainGenerator.plan(region, rng_seed, CATALOG, ENTITIES)
		_plans[key] = {"plan": plan, "shares": EcsTerrainGenerator.blend_shares(plan, region)}
	var p: Dictionary = _plans[key]
	return EcsSitePicker.pick(p["plan"], region, load(DEFS % town), rng_seed, ZOOM, CATALOG, p["shares"])

## Every size, on three kinds of water over several seeds: a main trade its survey supports, its
## core built, every role allowed by tier and survey, and food for everyone. Towns differ.
func _every_town_lives_on_what_it_has() -> Array[EcsSettlementSite]:
	var towns: Array[EcsSettlementSite] = []
	var seen: Dictionary = {}
	for town in TOWNS:
		var def := load(DEFS % town) as EcsSettlementDef
		var first := ""
		var lives: Dictionary = {}
		var usec := 0
		var mean: Dictionary = {}
		for water in WATERS:
			for s in SEEDS:
				var site := _pick(_region(water), s, town)
				if site == null:
					continue
				towns.append(site)
				var started := Time.get_ticks_usec()
				EcsTownEconomy.plan(EcsResourceSurvey.of(site, _plans[[water, 5, s]]["plan"], _region(water), def), def, s, site.l2_cell)
				usec += Time.get_ticks_usec() - started
				for key: StringName in site.survey:
					mean[key] = float(mean.get(key, 0.0)) + site.survey[key] / (SEEDS * WATERS.size())
				var problem := _problem(site, def)
				if problem != "" and first == "":
					first = "water %d seed %d: %s" % [water, s, problem]
				var name := String(site.economy["character"])
				if not (site.economy["sides"] as Array).is_empty():
					name += " + " + "/".join(site.economy["sides"])
				lives[name] = int(lives.get(name, 0)) + 1
				seen[site.economy["character"]] = true
		_check("%s: every town lives on what it has, builds its core and feeds itself%s" % [town, "" if first == "" else "  " + first], first == "")
		print("[economy]   %s: %s; survey and economy %d ms a town" % [town, lives, usec / maxi(SEEDS * WATERS.size(), 1) / 1000])
		print("[economy]   %s: mean survey %s" % [town, ", ".join(mean.keys().map(func(k: StringName) -> String: return "%s %.2f" % [k, mean[k]]))])
	_check("towns differ: %d main trades among them (%s)" % [seen.size(), ", ".join(seen.keys())], seen.size() >= 3)
	return towns

func _problem(site: EcsSettlementSite, def: EcsSettlementDef) -> String:
	var economy := site.economy
	var catalog := EcsTownEconomy.CATALOG
	var character: EcsSettlementCharacterDef = null
	for c in catalog.characters:
		if c.key == economy["character"]:
			character = c
	if character == null:
		return "no main trade"
	if not EcsResourceSurvey.holds(site.survey, character.requires, character.requires_any) or character.min_tier > def.tier:
		return "%s without what it needs" % character.key
	var built: Dictionary = {}
	for entry: Dictionary in economy["roles"]:
		var role := catalog.role(entry["role"])
		built[role.key] = true
		if role.min_tier > def.tier or not EcsResourceSurvey.holds(site.survey, role.requires, role.requires_any, role.absent):
			return "%s built without what it needs" % role.key
	for key: StringName in character.core:
		var role := catalog.role(key)
		if role.min_tier <= def.tier and EcsResourceSurvey.holds(site.survey, role.requires, role.requires_any, role.absent) and not built.has(key):
			return "%s's core role %s missing" % [character.key, key]
	if economy["fed"] < economy["population"]:
		return "%d people, food for %d" % [economy["population"], economy["fed"]]
	return ""

## A side line builds its small set: a town with mining on the side has a mine, and a toolsmith
## where the ore is iron or copper.
func _side_lines_build_their_small_set(towns: Array[EcsSettlementSite]) -> void:
	var mining := 0
	var whole := true
	for site in towns:
		if not (site.economy["sides"] as Array).has(&"mining"):
			continue
		mining += 1
		var built := (site.economy["roles"] as Array).map(func(e: Dictionary) -> StringName: return e["role"])
		var smiths := EcsResourceSurvey.holds(site.survey, [], [&"iron", &"copper"])
		whole = whole and built.has(&"mine") and built.has(&"toolsmith") == smiths
	_check("%d towns mine on the side, each with a mine, and a toolsmith who smelts where iron or copper is" % mining, mining > 0 and whole)

func _the_same_seed_gives_the_same_town() -> void:
	var a := _pick(_region(EcsSettlementDef.Water.RIVER_TO_SEA), 1, &"village")
	var b := _pick(_region(EcsSettlementDef.Water.RIVER_TO_SEA), 1, &"village")
	_check("the same seed gives the same town", a.economy == b.economy and a.survey == b.survey)

## With no deposits in the region, nothing mines.
func _no_deposits_means_no_mining() -> void:
	var miners := 0
	for s in SEEDS:
		var site := _pick(_region(EcsSettlementDef.Water.RIVER_TO_SEA, false), s, &"village")
		if site.economy["character"] == &"mining" or (site.economy["sides"] as Array).has(&"mining"):
			miners += 1
	_check("a region with no deposits has no mining town (%d seeds)" % SEEDS, miners == 0)

func _check(what: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
	print("[economy] %s  %s" % ["ok  " if passed else "FAIL", what])
