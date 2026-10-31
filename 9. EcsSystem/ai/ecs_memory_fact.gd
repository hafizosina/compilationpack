class_name EcsMemoryFact
extends RefCounted

## One remembered place: what was there, where it was seen, and how fresh that is.

## The entity remembered.
var about: int = EcsWorld.NO_ENTITY
## Where it was last seen. Trips go here, never to the live entity.
var position: Vector2 = Vector2.ZERO
## Remembered as water to drink.
var water: bool = false
## Remembered as a lure to wait in.
var lure: bool = false
## 1 when seen, fading to 0 while unseen.
var strength: float = 1.0

## The nearest fact in `memory` remembered as water (or as a lure), or null.
static func nearest(memory: EcsMemoryComponent, here: Vector2, water: bool) -> EcsMemoryFact:
	var best: EcsMemoryFact = null
	var best_distance := INF
	if memory == null:
		return best
	for about in memory.facts:
		var fact := memory.facts[about] as EcsMemoryFact
		if not (fact.water if water else fact.lure):
			continue
		var distance := here.distance_squared_to(fact.position)
		if distance < best_distance:
			best_distance = distance
			best = fact
	return best
