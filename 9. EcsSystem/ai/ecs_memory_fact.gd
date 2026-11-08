class_name EcsMemoryFact
extends RefCounted

## One remembered thing: what it was to the rememberer, where it was seen, and when, copied
## when it leaves sight; in sight, readers use the live entity. Fear and traffic are notes,
## written when learned. Freshness, fear and traffic are stored as times and worked out when
## read, against the memory's `as_of`.

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
## It can't move, so its position and radius are never read again.
var fixed: bool = false
## False once it was looked for where it was seen and wasn't there: who it is, kept; where, lost.
var placed: bool = true
## Its velocity when last seen, and its top speed.
var velocity: Vector2 = Vector2.ZERO
var speed: float = 0.0
## What it is to the rememberer, as kind bits.
var kinds: int = 0
## Clock time it was last seen.
var seen_at: float = 0.0
## In sight now: fresh, and its copy is not read.
var in_sight: bool = false
## Clock time a threat was last met here.
var feared_at: float = -INF
## Seconds of prey seen here as of `traffic_at`; a kill seen here adds more.
var traffic: float = 0.0
var traffic_at: float = 0.0
## Corpse ids already counted into `traffic`.
var kills_seen: Dictionary = {}

func is_a(kind: int) -> bool:
	return kinds & kind != 0

## 1 when just seen, fading to 0 over `remember_for`; 0 means forgotten.
static func strength_of(fact: EcsMemoryFact, memory: EcsMemoryComponent) -> float:
	if fact.in_sight:
		return 1.0
	return clampf(1.0 - (memory.as_of - fact.seen_at) / memory.remember_for, 0.0, 1.0)

## 1 when a threat was just met here, fading to 0 over `fear_for`.
static func fear_of(fact: EcsMemoryFact, memory: EcsMemoryComponent) -> float:
	return maxf(1.0 - (memory.as_of - fact.feared_at) / memory.fear_for, 0.0)

## How far it may have gone since it was seen; 0 for a thing that can't move.
static func spread_of(fact: EcsMemoryFact, memory: EcsMemoryComponent) -> float:
	if fact.in_sight:
		return 0.0
	return fact.speed * (memory.as_of - fact.seen_at)

## Worth acting on: not forgotten, with a place, and not gone farther than it can follow.
static func usable(fact: EcsMemoryFact, memory: EcsMemoryComponent) -> bool:
	return fact.placed and strength_of(fact, memory) > 0.0 \
		and spread_of(fact, memory) <= memory.lose_track_at

## Its traffic now, halving every `traffic_half_life`.
static func traffic_of(fact: EcsMemoryFact, memory: EcsMemoryComponent) -> float:
	if fact.traffic == 0.0:
		return 0.0
	return fact.traffic * pow(0.5, (memory.as_of - fact.traffic_at) / memory.traffic_half_life)

## What going to `fact` costs a plan: the walk, plus searching as far as it may have gone, plus
## fear (met here, or a remembered threat near it), plus the expected wait if it is a lure.
static func score(fact: EcsMemoryFact, memory: EcsMemoryComponent, here: Vector2, speed: float,
		kind: int) -> float:
	return _price(memory, fact, fact.position, fact.radius, spread_of(fact, memory), here, speed, kind)

## What going to `about`, in sight at `position` with body `radius`, costs a plan: the walk, plus
## the notes memory holds on it (fear, a lure's wait) and any remembered threat near it.
static func score_at(memory: EcsMemoryComponent, about: int, position: Vector2, radius: float,
		here: Vector2, speed: float, kind: int) -> float:
	return _price(memory, memory.facts.get(about) as EcsMemoryFact, position, radius, 0.0, here, speed, kind)

static func _price(memory: EcsMemoryComponent, note: EcsMemoryFact, position: Vector2, radius: float,
		spread: float, here: Vector2, speed: float, kind: int) -> float:
	var cost := 1.0 + (here.distance_to(position) + spread) / speed / TRAVEL_SECONDS
	var fear := fear_of(note, memory) if note != null else 0.0
	cost += memory.fear_cost * maxf(fear, threat_near(memory, position, radius))
	if kind == LURE:
		cost += memory.wait_cost / (1.0 + (traffic_of(note, memory) if note != null else 0.0))
	return cost

## The strongest remembered threat within `near` of a place at `position` with `radius`, 0 if none.
static func threat_near(memory: EcsMemoryComponent, position: Vector2, radius: float) -> float:
	var found := 0.0
	var reach := radius + memory.near
	for about in memory.facts:
		var other := memory.facts[about] as EcsMemoryFact
		if not other.is_a(THREAT) or not other.placed:
			continue
		if other.position.distance_squared_to(position) <= reach * reach:
			found = maxf(found, strength_of(other, memory))
	return found

## The cheapest fact in `memory` of `kind` about something out of sight, or null.
static func best(memory: EcsMemoryComponent, here: Vector2, speed: float, kind: int) -> EcsMemoryFact:
	var found: EcsMemoryFact = null
	var found_score := INF
	if memory == null:
		return found
	for about in memory.facts:
		var fact := memory.facts[about] as EcsMemoryFact
		if fact.in_sight or not fact.is_a(kind) or not usable(fact, memory):
			continue
		var cost := score(fact, memory, here, speed, kind)
		if cost < found_score:
			found_score = cost
			found = fact
	return found
