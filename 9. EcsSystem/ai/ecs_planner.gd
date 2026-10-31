class_name EcsPlanner
extends RefCounted

## Forward A* over facts. Pure: reads only its arguments, so it can run off the
## main thread later.

## Longest plan it searches for.
const MAX_DEPTH: int = 8

## The cheapest action ids that take `state` to one where every fact in `desired`
## holds. Empty if `desired` already holds or no plan fits in MAX_DEPTH.
static func plan(state: Dictionary, desired: Dictionary,
		actions: Array[EcsActionDef]) -> Array[StringName]:
	var none: Array[StringName] = []
	var open: Array[Dictionary] = [{"state": state, "g": 0.0,
		"f": _estimate(state, desired), "steps": none}]
	var best := {_key(state): 0.0}
	while not open.is_empty():
		var at := _pop_cheapest(open)
		var facts: Dictionary = at["state"]
		var steps: Array[StringName] = at["steps"]
		if holds(facts, desired):
			return steps
		if steps.size() >= MAX_DEPTH:
			continue
		for action in actions:
			if not holds(facts, action.preconditions):
				continue
			var next := facts.duplicate()
			next.merge(action.effects, true)
			var g: float = at["g"] + action.cost
			var key := _key(next)
			if best.has(key) and best[key] <= g:
				continue
			best[key] = g
			var longer := steps.duplicate()
			longer.append(action.id)
			open.append({"state": next, "g": g, "f": g + _estimate(next, desired),
				"steps": longer})
	return none

## Does every fact in `wanted` hold in `facts`? A missing fact is false.
static func holds(facts: Dictionary, wanted: Dictionary) -> bool:
	for fact in wanted:
		if facts.get(fact, false) != wanted[fact]:
			return false
	return true

## 0 when done, else 1: admissible while every action costs at least 1.
static func _estimate(facts: Dictionary, desired: Dictionary) -> float:
	return 0.0 if holds(facts, desired) else 1.0

static func _key(facts: Dictionary) -> String:
	var true_facts := PackedStringArray()
	for fact in facts:
		if facts[fact]:
			true_facts.append(fact)
	true_facts.sort()
	return ",".join(true_facts)

static func _pop_cheapest(open: Array[Dictionary]) -> Dictionary:
	var pick := 0
	for k in range(1, open.size()):
		if open[k]["f"] < open[pick]["f"]:
			pick = k
	var at := open[pick]
	open.remove_at(pick)
	return at
