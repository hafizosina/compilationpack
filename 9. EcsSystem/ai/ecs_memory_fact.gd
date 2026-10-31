class_name EcsMemoryFact
extends RefCounted

## One remembered thing: what it was to the rememberer, where it was seen, and how fresh
## that is. Each sighting rewrites `kinds`, so an emptied bush stops being food.

## Seconds of travel that cost one unit of a plan.
const TRAVEL_SECONDS: float = 5.0

## Kinds, as bits of `kinds`.
const WATER: int = 1   ## Water it drinks.
const LURE: int = 2    ## Cover it hides in that prey must visit.
const FOOD: int = 4    ## Food of its diet.
const BUSH: int = 8    ## A bush whose yield is its diet, not empty.
const THREAT: int = 16 ## Something that can hunt it.
const PREY: int = 32   ## Something it can hunt.
const MATE: int = 64   ## One of its kind, ready to breed.

## The entity remembered.
var about: int = EcsWorld.NO_ENTITY
## Where it was last seen. Trips go here, never to the live entity.
var position: Vector2 = Vector2.ZERO
## Its body radius when seen.
var radius: float = 0.0
## What it is to the rememberer, as kind bits.
var kinds: int = 0
## 1 when seen, fading to 0 while unseen.
var strength: float = 1.0
## 1 when a threat was met here, fading to 0.
var fear: float = 0.0
## Seconds of prey seen here, fading; a kill seen here adds more.
var traffic: float = 0.0
## Corpse ids already counted into `traffic`.
var kills_seen: Dictionary = {}

func is_a(kind: int) -> bool:
	return kinds & kind != 0

## What going to `fact` costs a plan: the walk, plus fear (met here, or a remembered threat
## near it), plus the expected wait if it is a lure taken as one.
static func score(fact: EcsMemoryFact, memory: EcsMemoryComponent, here: Vector2, speed: float,
		kind: int) -> float:
	var cost := 1.0 + here.distance_to(fact.position) / speed / TRAVEL_SECONDS
	cost += memory.fear_cost * maxf(fact.fear, threat_near(memory, fact))
	if kind == LURE:
		cost += memory.wait_cost / (1.0 + fact.traffic)
	return cost

## The strongest remembered threat within `near` of `fact`, 0 if none.
static func threat_near(memory: EcsMemoryComponent, fact: EcsMemoryFact) -> float:
	var found := 0.0
	for about in memory.facts:
		var other := memory.facts[about] as EcsMemoryFact
		if not other.is_a(THREAT):
			continue
		var reach := fact.radius + memory.near
		if other.position.distance_squared_to(fact.position) <= reach * reach:
			found = maxf(found, other.strength)
	return found

## The cheapest fact in `memory` of `kind`, or null. With `in_sight`, only facts about
## entities in `seen`.
static func best(memory: EcsMemoryComponent, here: Vector2, speed: float, kind: int,
		in_sight: bool = false, seen: Array[int] = []) -> EcsMemoryFact:
	var found: EcsMemoryFact = null
	var found_score := INF
	if memory == null:
		return found
	for about in memory.facts:
		var fact := memory.facts[about] as EcsMemoryFact
		if not fact.is_a(kind):
			continue
		if in_sight and not seen.has(about):
			continue
		var cost := score(fact, memory, here, speed, kind)
		if cost < found_score:
			found_score = cost
			found = fact
	return found
