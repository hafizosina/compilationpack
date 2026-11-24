class_name WorldTownCensus
extends RefCounted

## Pure and seeded: a town's people before its buildings (BETTER_TOWNS_PLAN.md §C).
##   1. The main trade: every character its tier allows and its survey supports is scored; the best.
##   2. Traffic: a level rolled (a trading town's raised), and how many travellers a day.
##   3. People: the population rolled in the tier's range, split into households.
##   4. Makers: for each resource, what the people need, made by its makers up to what the land in
##      reach allows; the main trade makes `surplus` times the need, or its trade good for export.
##      Middling and richer rice farmers get a buffalo while herders and traders have them.
##   5. Services one per so many people, fixed ones per town, inns and entertainment by traffic,
##      then what serves another role (a rice barn per so many farms).
##   6. Each workplace with workers goes to a family, which takes its wealth, the most needed first
##      (food, other needs, services, traffic's, trade goods, then what serves another role); one
##      without a family is dropped. The village head's family is rich; in a busy town innkeepers and
##      traders are a step richer.
##   7. A family lives at its workplace when the role says so and it isn't rich; every other family
##      gets a house by its wealth. A house's rooms follow its family (sleeping rooms by wealth and
##      size); a workplace lived in gains a store and the family's living rooms.
##   8. Whether each maker sells from home, by its role's chance; the rest sell at the market.

const CATALOG := preload("res://13. World Generator/defs/economy.tres")
## Households: [weight, adults min, adults max, children min, children max, elders].
const HOUSEHOLDS := [[0.1, 1, 1, 0, 0, 0], [0.2, 2, 2, 0, 0, 0], [0.5, 2, 2, 1, 4, 0], [0.2, 2, 3, 1, 3, 1]]
## Traffic levels: name, roll weight, travellers a day.
const TRAFFIC := [[&"quiet", 0.35, Vector2i(0, 5)], [&"steady", 0.35, Vector2i(5, 20)], [&"busy", 0.2, Vector2i(20, 60)],
	[&"crossroads", 0.1, Vector2i(60, 120)]]
## Share of travellers who stay the night.
const STAY: float = 0.3
## The catchment the roles' capacities are given for; a bigger one holds more by its area.
const CAPACITY_AT: float = 40.0
## Buffalo traders bring a year, by traffic level.
const BUFFALO_BOUGHT: Array[int] = [1, 3, 6, 10]
const RICE_FARM := &"rice_farm"
const BUFFALO_FARM := &"buffalo_farm"
const BUFFALO_HERDER := &"buffalo_herder"
const HEAD_HOUSE := &"head_house"
## Room types the census adds: where a family sleeps, cooks and stores.
const BEDROOM := &"bedroom"
const KITCHEN := &"kitchen"
const STORE := &"store"
## A family with no workplace: its chances of being poor, middling and rich.
const LABOURER_ODDS := Vector3(0.8, 0.2, 0.0)

## {character, scores, traffic: {level, name, travellers}, population, families: [{people, adults,
## children, elders, job, wealth, home}], resources: {key: {need, made, imported, exported}},
## roles: [{role, count, from, wealths, sells: whether each sells from home, rooms: each one's room
## list, [] for its role's}], labourers, short_of_people: {role: count}, short_of_workers}.
static func plan(facts: Dictionary, def: WorldSettlementDef, rng_seed: int, l2_cell: Vector2i) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([rng_seed, l2_cell, &"census"])
	var scores: Dictionary = {}
	var main := _main_trade(facts, def, scores)
	var level := _roll(rng, TRAFFIC.map(func(t: Array) -> float: return t[1]))
	if main != null and main.traffic_bonus > 0:
		level = clampi(maxi(level + main.traffic_bonus, 2), 0, TRAFFIC.size() - 1)
	var span: Vector2i = TRAFFIC[level][2]
	var travellers := roundi(rng.randi_range(span.x, span.y) * def.traffic_scale)
	var population := rng.randi_range(def.population.x, def.population.y)
	var families := _families(population, rng)
	var out := {"character": main.key if main != null else &"", "scores": scores,
		"traffic": {"level": level, "name": TRAFFIC[level][0], "travellers": travellers}, "population": population,
		"resources": {}, "labourers": 0, "short_of_people": {}, "short_of_workers": 0}
	var counts: Dictionary = {}
	var from: Dictionary = {}
	var wealths: Dictionary = {}
	var scale := pow(def.catchment / CAPACITY_AT, 2.0)
	var farm_target := 0.0
	for resource in CATALOG.resources:
		if resource.key == &"buffalo":
			continue
		var made := _make(resource, facts, def, main, population, scale, counts, from, wealths, rng)
		out["resources"][resource.key] = made
		if resource.key == &"food":
			farm_target = made["by"].get(RICE_FARM, 0.0)
	_buffalo(facts, def, level, scale, farm_target, counts, from, wealths, rng)
	var people := population + travellers
	var ranks: Dictionary = {}
	for role in CATALOG.roles:
		if not _allowed(role, facts, def.tier) or role.serves != &"" or role.home >= 0 or role.makes != &"":
			continue
		if role.traffic_min >= 0 and level < role.traffic_min:
			continue
		var n := 0
		if role.travellers_per > 0:
			n = roundi(travellers * STAY / role.travellers_per)
		elif role.per_town > 0:
			n = role.per_town
		elif role.per_people > 0:
			n = ceili(ceilf(float(people) / role.per_people) / maxi(role.places, 1))
		_put(role, n, &"traffic" if role.traffic_min >= 0 else &"service", level, counts, from, wealths, rng)
	var order := _order(families, rng)
	var next := _settle(out, families, order, 0, counts, wealths, counts.keys(), rng, from)
	var chained: Array = []
	for role in CATALOG.roles:
		if role.serves == &"" or not _allowed(role, facts, def.tier):
			continue
		var served: int = counts.get(role.serves, 0) + (counts.get(BUFFALO_FARM, 0) if role.serves == RICE_FARM else 0)
		_put(role, roundi(float(served) / role.per_served), &"chain", level, counts, from, wealths, rng)
		chained.append(role.key)
	next = _settle(out, families, order, next, counts, wealths, chained, rng, from)
	_house(out, families, order, next, counts, from, wealths, rng)
	_tally(out, population, counts)
	out["families"] = families
	var rooms := _rooms(families, counts)
	var roles: Array[Dictionary] = []
	for key: StringName in counts:
		if counts[key] > 0:
			var role := CATALOG.role(key)
			var sells: Array = []
			for k in counts[key]:
				sells.append(role.sells_at_home > 0.0 and rng.randf() < role.sells_at_home)
			roles.append({"role": key, "count": counts[key], "from": from[key], "wealths": wealths[key], "sells": sells,
				"rooms": rooms.get(key, [])})
	out["roles"] = roles
	return out

## The best-scoring character this town's tier and survey allow, or null; fills `scores`.
static func _main_trade(facts: Dictionary, def: WorldSettlementDef, scores: Dictionary) -> WorldSettlementCharacterDef:
	var best: WorldSettlementCharacterDef = null
	for character in CATALOG.characters:
		if character.min_tier > def.tier or not WorldResourceSurvey.holds(facts, character.requires, character.requires_any):
			continue
		var score := 0.0
		for key in character.weights:
			score += character.weights[key] * facts.get(key, 0.0)
		scores[character.key] = score
		if best == null or score > scores[best.key] or (score == scores[best.key] and character.key < best.key):
			best = character
	return best

## Households rolled until `population` is reached, the last trimmed to fit.
static func _families(population: int, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var left := population
	while left > 0:
		var h: Array = HOUSEHOLDS[_roll(rng, HOUSEHOLDS.map(func(x: Array) -> float: return x[0]))]
		var adults := rng.randi_range(h[1], h[2])
		var children := rng.randi_range(h[3], h[4])
		var elders: int = h[5]
		var over := adults + children + elders - left
		while over > 0:
			if children > 0:
				children -= 1
			elif elders > 0:
				elders -= 1
			else:
				adults -= 1
			over -= 1
		left -= adults + children + elders
		out.append({"people": adults + children + elders, "adults": adults, "children": children, "elders": elders,
			"job": &"", "wealth": 0, "home": &""})
	return out

## Makers of `resource` up to what is needed (or exported), each held to what the land allows.
static func _make(resource: WorldResourceDef, facts: Dictionary, def: WorldSettlementDef, main: WorldSettlementCharacterDef,
		population: int, scale: float, counts: Dictionary, from: Dictionary, wealths: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	var makers: Array[WorldSettlementRoleDef] = []
	for role in CATALOG.roles:
		if role.makes == resource.key and role.key != BUFFALO_FARM and _allowed(role, facts, def.tier):
			makers.append(role)
	var exporter: StringName = main.exports if main != null else &""
	makers.sort_custom(func(a: WorldSettlementRoleDef, b: WorldSettlementRoleDef) -> bool:
		if (a.key == exporter) != (b.key == exporter):
			return a.key == exporter
		var fa: float = facts.get(a.capacity_fact, 1.0) if a.capacity_fact != &"" else 1.0
		var fb: float = facts.get(b.capacity_fact, 1.0) if b.capacity_fact != &"" else 1.0
		return fa > fb if fa != fb else a.key < b.key)
	var need := population * resource.per_person
	var exports := makers.any(func(r: WorldSettlementRoleDef) -> bool: return r.key == exporter)
	var target := need * (def.surplus if exports else 1.0)
	if resource.per_person == 0.0 and exports:
		target = population * resource.export_per_person * def.surplus
	var left := target
	var by: Dictionary = {}
	for role in makers:
		var cap := 1 << 20
		if role.capacity_fact != &"":
			cap = floori(role.capacity * facts.get(role.capacity_fact, 0.0) * scale)
		var n := mini(ceili(maxf(left, 0.0) / role.output), cap)
		if resource.per_person == 0.0 and role.key != exporter:
			n = mini(1, cap) if def.tier >= 1 else 0
		_put(role, n, &"make", 0, counts, from, wealths, rng)
		left -= n * role.output
		by[role.key] = n * role.output
	var made := target - maxf(left, 0.0)
	return {"need": need, "made": made, "imported": maxf(need - made, 0.0), "exported": maxf(made - need, 0.0), "by": by}

## Middling and richer rice farmers get a buffalo while herders and traders have them; with the
## buffalo, fewer farms make the same rice.
static func _buffalo(facts: Dictionary, def: WorldSettlementDef, level: int, scale: float, farm_target: float,
		counts: Dictionary, from: Dictionary, wealths: Dictionary, rng: RandomNumberGenerator) -> void:
	var farm := CATALOG.role(RICE_FARM)
	var upgraded := CATALOG.role(BUFFALO_FARM)
	var herder := CATALOG.role(BUFFALO_HERDER)
	var farm_wealths: Array = wealths.get(RICE_FARM, [])
	var wanting := farm_wealths.filter(func(w: int) -> bool: return w >= 1).size()
	if wanting == 0 or upgraded == null:
		return
	var herders := 0
	if herder != null and _allowed(herder, facts, def.tier):
		herders = mini(ceili(wanting / herder.output), floori(herder.capacity * facts.get(herder.capacity_fact, 0.0) * scale))
		_put(herder, herders, &"make", 0, counts, from, wealths, rng)
	var given := mini(wanting, herders * int(herder.output if herder != null else 0.0) + BUFFALO_BOUGHT[level])
	var kept: Array = []
	var moved: Array = []
	for w: int in farm_wealths:
		if w >= 1 and moved.size() < given:
			moved.append(w)
		else:
			kept.append(w)
	# Fewer hand farms are needed once the buffalo farms make more.
	kept.sort()
	while not kept.is_empty() and kept.size() * farm.output + moved.size() * upgraded.output - farm.output >= farm_target:
		kept.pop_front()
	counts[RICE_FARM] = kept.size()
	wealths[RICE_FARM] = kept
	counts[BUFFALO_FARM] = moved.size()
	from[BUFFALO_FARM] = &"make"
	wealths[BUFFALO_FARM] = moved

## Adds `n` of `role`, each rolling its owner's wealth (or taking the role's when nobody owns it).
static func _put(role: WorldSettlementRoleDef, n: int, kind: StringName, level: int, counts: Dictionary, from: Dictionary,
		wealths: Dictionary, rng: RandomNumberGenerator) -> void:
	if n <= 0:
		return
	counts[role.key] = int(counts.get(role.key, 0)) + n
	from[role.key] = kind
	var list: Array = wealths.get(role.key, [])
	for k in n:
		var w := role.wealth
		if role.places > 0:
			w = _roll(rng, [role.wealth_odds.x, role.wealth_odds.y, role.wealth_odds.z])
			if level >= 2 and (role.travellers_per > 0 or role.group == &"trade"):
				w = mini(w + 1, 2)
		list.append(w)
	wealths[role.key] = list

## Families in a seeded random order, the village head's first.
static func _order(families: Array[Dictionary], rng: RandomNumberGenerator) -> Array[int]:
	var order: Array[int] = []
	for k in families.size():
		order.append(k)
	for k in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var t := order[k]
		order[k] = order[j]
		order[j] = t
	return order

## Which workplaces get a family first when there aren't enough: food, then the other needs,
## services, traffic's, trade goods; within each, by priority.
static func _rank(role: WorldSettlementRoleDef, kind: StringName) -> int:
	if role.makes == &"food":
		return 0
	if role.makes != &"":
		var resource := CATALOG.resource(role.makes)
		return 1 if resource == null or resource.per_person > 0.0 or role.key == BUFFALO_HERDER else 4
	return {&"service": 2, &"traffic": 3, &"chain": 5}.get(kind, 2)

## Hands the workplaces of `keys` that have workers to families from `order[next]` on, most needed
## first; those left without a family are dropped and counted short. The next family free.
static func _settle(out: Dictionary, families: Array[Dictionary], order: Array[int], next: int, counts: Dictionary,
		wealths: Dictionary, keys: Array, rng: RandomNumberGenerator, from: Dictionary) -> int:
	if next == 0:
		var head := CATALOG.role(HEAD_HOUSE)
		if head != null and not order.is_empty():
			var family := families[order[0]]
			next = 1
			family["job"] = &"village_head"
			family["wealth"] = 2
			family["home"] = HEAD_HOUSE
			family["home_at"] = 0
			_put(head, 1, &"home", 0, counts, from, wealths, rng)
	var sorted := keys.duplicate()
	sorted.sort_custom(func(a: StringName, b: StringName) -> bool:
		var ra := CATALOG.role(a)
		var rb := CATALOG.role(b)
		var ka := _rank(ra, from.get(a, &""))
		var kb := _rank(rb, from.get(b, &""))
		if ka != kb:
			return ka < kb
		return ra.priority > rb.priority if ra.priority != rb.priority else a < b)
	for key: StringName in sorted:
		var role := CATALOG.role(key)
		if role.places <= 0 or role.home >= 0:
			continue
		var kept: Array = []
		for w: int in wealths.get(key, []):
			if next >= order.size():
				out["short_of_people"][key] = int(out["short_of_people"].get(key, 0)) + 1
				continue
			var family := families[order[next]]
			next += 1
			family["job"] = key
			family["wealth"] = w
			family["home"] = &"work" if role.lives_at_work and w < 2 else &""
			family["work_at"] = kept.size()
			kept.append(w)
		counts[key] = kept.size()
		wealths[key] = kept
	return next

## Labourers for the families with no workplace, and a house by its wealth for every family not
## living at its work.
static func _house(out: Dictionary, families: Array[Dictionary], order: Array[int], next: int, counts: Dictionary,
		from: Dictionary, wealths: Dictionary, rng: RandomNumberGenerator) -> void:
	var places := 0
	var owners_adults := 0
	for family in families:
		var role := CATALOG.role(family["job"])
		if role != null and role.places > 0:
			places += role.places
			owners_adults += mini(family["adults"], role.places)
	var spare := 0
	for k in range(next, order.size()):
		var family := families[order[k]]
		family["job"] = &"labourer"
		family["wealth"] = _roll(rng, [LABOURER_ODDS.x, LABOURER_ODDS.y, LABOURER_ODDS.z])
		spare += family["adults"]
	var hired := mini(spare, places - owners_adults)
	out["labourers"] = spare - hired
	out["short_of_workers"] = places - owners_adults - hired
	var homes: Array[WorldSettlementRoleDef] = []
	for role in CATALOG.roles:
		if role.home >= 0 and role.home <= 2:
			homes.append(role)
	for family in families:
		if family["home"] != &"":
			continue
		for role in homes:
			if role.home == family["wealth"]:
				family["home"] = role.key
				counts[role.key] = int(counts.get(role.key, 0)) + 1
				from[role.key] = &"home"
				var list: Array = wealths.get(role.key, [])
				family["home_at"] = list.size()
				list.append(family["wealth"])
				wealths[role.key] = list
				break

## What the makers left standing make, against what is needed.
static func _tally(out: Dictionary, population: int, counts: Dictionary) -> void:
	for key: StringName in out["resources"]:
		var made := 0.0
		for role in CATALOG.roles:
			if role.makes == key:
				made += role.output * int(counts.get(role.key, 0))
		var r: Dictionary = out["resources"][key]
		r["made"] = made
		r["imported"] = maxf(r["need"] - made, 0.0)
		r["exported"] = maxf(made - r["need"], 0.0)
		r.erase("by")

## Each building's rooms where a family lives in it ([] keeps its role's): a house's by its
## family's wealth and size, a workplace's own with the family's living rooms and a store added.
static func _rooms(families: Array[Dictionary], counts: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for family in families:
		var key: StringName = family["job"] if family["home"] == &"work" else family["home"]
		var at: int = family.get("work_at", 0) if family["home"] == &"work" else family.get("home_at", 0)
		var role := CATALOG.role(key)
		if role == null or role.home == 3:
			continue
		var list: Array = out.get(key, [])
		while list.size() < int(counts.get(key, 0)):
			list.append([])
		var rooms: Array[StringName] = role.rooms.duplicate()
		var wealth: int = family["wealth"]
		var sleeping := 0
		if wealth == 1:
			sleeping = 1 if family["people"] <= 4 else 2
		elif wealth == 2:
			sleeping = ceili(family["adults"] / 2.0) + (1 if family["children"] > 0 else 0)
		if family["home"] == &"work":
			sleeping = maxi(sleeping, 1)
			if wealth >= 1 and not rooms.has(KITCHEN):
				rooms.append(KITCHEN)
			if not rooms.has(STORE):
				rooms.append(STORE)
		else:
			sleeping = maxi(sleeping - rooms.count(BEDROOM), 0)
		for k in sleeping:
			rooms.append(BEDROOM)
		if at < list.size():
			list[at] = rooms
		out[key] = list
	return out

static func _allowed(role: WorldSettlementRoleDef, facts: Dictionary, tier: int) -> bool:
	return role.min_tier <= tier and tier <= role.max_tier \
		and WorldResourceSurvey.holds(facts, role.requires, role.requires_any, role.absent)

## An index picked by `weights`.
static func _roll(rng: RandomNumberGenerator, weights: Array) -> int:
	var total := 0.0
	for w: float in weights:
		total += w
	var at := rng.randf() * total
	for k in weights.size():
		at -= weights[k]
		if at < 0.0:
			return k
	return weights.size() - 1
