class_name EcsMemoryFact
extends RefCounted

## One remembered place: what was there, where it was seen, and how fresh that is.

## Seconds of travel that cost one unit of a plan.
const TRAVEL_SECONDS: float = 5.0

## The entity remembered.
var about: int = EcsWorld.NO_ENTITY
## Where it was last seen. Trips go here, never to the live entity.
var position: Vector2 = Vector2.ZERO
## Its body radius when seen.
var radius: float = 0.0
## Remembered as water to drink.
var water: bool = false
## Remembered as a lure to wait in.
var lure: bool = false
## 1 when seen, fading to 0 while unseen.
var strength: float = 1.0
## 1 when a threat was met here, fading to 0.
var fear: float = 0.0
## Seconds of prey seen here, fading; a kill seen here adds more.
var traffic: float = 0.0
## Corpse ids already counted into `traffic`.
var kills_seen: Dictionary = {}

## What going to `fact` costs a plan: the walk, plus fear for water or the expected wait
## for a lure.
static func score(fact: EcsMemoryFact, memory: EcsMemoryComponent, here: Vector2, speed: float,
		water: bool) -> float:
	var cost := 1.0 + here.distance_to(fact.position) / speed / TRAVEL_SECONDS
	if water:
		return cost + memory.fear_cost * fact.fear
	return cost + memory.wait_cost / (1.0 + fact.traffic)

## The cheapest fact in `memory` remembered as water (or as a lure), or null. With
## `in_sight`, only facts about entities in `seen`.
static func best(memory: EcsMemoryComponent, here: Vector2, speed: float, water: bool,
		in_sight: bool = false, seen: Array[int] = []) -> EcsMemoryFact:
	var found: EcsMemoryFact = null
	var found_score := INF
	if memory == null:
		return found
	for about in memory.facts:
		var fact := memory.facts[about] as EcsMemoryFact
		if not (fact.water if water else fact.lure):
			continue
		if in_sight and not seen.has(about):
			continue
		var cost := score(fact, memory, here, speed, water)
		if cost < found_score:
			found_score = cost
			found = fact
	return found
