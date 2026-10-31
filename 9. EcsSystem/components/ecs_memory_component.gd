class_name EcsMemoryComponent
extends EcsComponent

## Places it has seen and may walk back to. Only EcsMemorySystem writes it.

## Most facts kept; past this the weakest is forgotten.
@export var capacity: int = 32
## Seconds unseen before a fact fades out.
@export var remember_for: float = 180.0
## How close to a place counts as at it, beyond its radius.
@export var near: float = 200.0
## Seconds for a fear to fade.
@export var fear_for: float = 60.0
## Plan cost of full fear at a pond.
@export var fear_cost: float = 4.0
## Seconds for a lure's traffic to halve.
@export var traffic_half_life: float = 120.0
## Plan cost of waiting at a lure with no traffic.
@export var wait_cost: float = 2.0
## Traffic a corpse seen at a lure adds.
@export var kill_traffic: float = 10.0

## Remembered entity id -> EcsMemoryFact.
var facts: Dictionary = {}

func key() -> StringName:
	return &"memory"

func describe() -> Dictionary:
	var lines := {}
	for about in facts:
		var fact := facts[about] as EcsMemoryFact
		var kind := "water" if fact.water else ""
		if fact.lure:
			kind = "lure" if kind.is_empty() else kind + ", lure"
		var text := "%d%% at (%d, %d)" % [roundi(fact.strength * 100.0),
			roundi(fact.position.x), roundi(fact.position.y)]
		if fact.fear > 0.0:
			text += ", fear %d%%" % roundi(fact.fear * 100.0)
		if fact.traffic > 0.0:
			text += ", traffic %.1f" % fact.traffic
		lines["#%d %s" % [about, kind]] = text
	return {"tab": &"own", "lines": lines}
