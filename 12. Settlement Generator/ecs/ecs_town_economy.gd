class_name EcsTownEconomy
extends RefCounted

## Pure and seeded: what a town is and which buildings it has, from its survey and tier.
##   1. Every character its tier allows and its survey supports is scored; the best is the main
##      trade.
##   2. Others scoring their `side_at` or more are side lines, at most MAX_SIDES, those clearing it
##      furthest first.
##   3. Roles: the tier's base, the main trade's core scaled by the tier, each side line's small set;
##      a role whose tier or survey facts don't allow it is left out.
##   4. Food: while the town's people outnumber what it feeds, the first food role it can have is
##      added. A trading town buys part of its food.

const CATALOG := preload("res://12. Settlement Generator/defs/economy.tres")
const MAX_SIDES: int = 2
## Share of its food a trading town buys.
const BOUGHT: float = 0.3
## Most food roles added.
const MAX_FOOD: int = 300

## {character, scores: {key: score}, sides: [key], roles: [{role, count, from: base, core, side or
## food}], left_out: [role key], population, fed}.
static func plan(facts: Dictionary, def: EcsSettlementDef, rng_seed: int, l2_cell: Vector2i) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([rng_seed, l2_cell, &"economy"])
	var scores: Dictionary = {}
	var ranked: Array[EcsSettlementCharacterDef] = []
	for character in CATALOG.characters:
		if character.min_tier > def.tier or not EcsResourceSurvey.holds(facts, character.requires, character.requires_any):
			continue
		var score := 0.0
		for key in character.weights:
			score += character.weights[key] * facts.get(key, 0.0)
		scores[character.key] = score
		ranked.append(character)
	ranked.sort_custom(func(a: EcsSettlementCharacterDef, b: EcsSettlementCharacterDef) -> bool:
		if scores[a.key] != scores[b.key]:
			return scores[a.key] > scores[b.key]
		return a.key < b.key)
	var out := {"character": &"", "scores": scores, "sides": [] as Array[StringName], "roles": [] as Array[Dictionary],
		"left_out": [] as Array[StringName], "population": 0, "fed": 0}
	var counts: Dictionary = {}
	_add(out, counts, def.base_roles, 1.0, &"base", facts, def.tier, rng)
	if not ranked.is_empty():
		out["character"] = ranked[0].key
		_add(out, counts, ranked[0].core, def.trade_scale, &"core", facts, def.tier, rng)
		# Side lines in order of how far each clears its own threshold.
		var others := ranked.slice(1)
		others.sort_custom(func(x: EcsSettlementCharacterDef, y: EcsSettlementCharacterDef) -> bool:
			var dx: float = scores[x.key] - x.side_at
			var dy: float = scores[y.key] - y.side_at
			return dx > dy if dx != dy else x.key < y.key)
		for character in others:
			if (out["sides"] as Array).size() >= MAX_SIDES:
				break
			if scores[character.key] >= character.side_at and not character.side.is_empty():
				(out["sides"] as Array[StringName]).append(character.key)
				_add(out, counts, character.side, 1.0, &"side", facts, def.tier, rng)
	var buys: bool = out["character"] == &"trading" or (out["sides"] as Array).has(&"trading")
	for n in MAX_FOOD:
		_tally(out, counts, buys)
		if out["fed"] >= out["population"]:
			break
		var added := false
		for key in CATALOG.food_roles:
			if _allowed(CATALOG.role(key), facts, def.tier):
				_put(out, counts, key, 1, &"food")
				added = true
				break
		if not added:
			break
	var roles: Array[Dictionary] = []
	for key: StringName in counts:
		roles.append(counts[key])
	out["roles"] = roles
	return out

## Adds `range_of` roles (key -> count range), each count picked and scaled, the ones not allowed
## listed in `left_out`.
static func _add(out: Dictionary, counts: Dictionary, range_of: Dictionary, scale: float, from: StringName,
		facts: Dictionary, tier: int, rng: RandomNumberGenerator) -> void:
	for key: StringName in range_of:
		var span: Vector2i = range_of[key]
		var count := rng.randi_range(span.x, span.y)
		if scale != 1.0:
			count = maxi(roundi(count * scale), mini(span.x, 1))
		if count <= 0:
			continue
		if not _allowed(CATALOG.role(key), facts, tier):
			if not (out["left_out"] as Array).has(key):
				(out["left_out"] as Array[StringName]).append(key)
			continue
		_put(out, counts, key, count, from)

static func _put(_out: Dictionary, counts: Dictionary, key: StringName, count: int, from: StringName) -> void:
	if counts.has(key):
		counts[key]["count"] += count
	else:
		counts[key] = {"role": key, "count": count, "from": from}

static func _allowed(role: EcsSettlementRoleDef, facts: Dictionary, tier: int) -> bool:
	return role != null and role.min_tier <= tier and EcsResourceSurvey.holds(facts, role.requires, role.requires_any, role.absent)

## The town's population and the people it feeds.
static func _tally(out: Dictionary, counts: Dictionary, buys: bool) -> void:
	var people := 0
	var fed := 0
	for key: StringName in counts:
		var role := CATALOG.role(key)
		people += role.residents * int(counts[key]["count"])
		fed += role.feeds * int(counts[key]["count"])
	if buys:
		fed += roundi(people * BOUGHT)
	out["population"] = people
	out["fed"] = fed
