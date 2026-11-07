class_name EcsMemoryComponent
extends EcsComponent

## What it has seen that matters to it, and where. Only EcsMemorySystem writes it.

## Kind bit -> its name, for describe().
const KIND_NAMES: Dictionary = {1: "water", 2: "lure", 4: "food", 8: "bush", 16: "threat", 32: "prey",
	64: "mate"}

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
## How far a moving thing may have gone, in px, before its last spot is no use.
@export var lose_track_at: float = 600.0

## Remembered entity id -> EcsMemoryFact.
var facts: Dictionary = {}
## Clock time of its last memory run; facts' ages are read against it.
var as_of: float = 0.0
## The trip destination last matched to a fact, and that fact's id (or none). Only the fact it
## is walking to is checked against what it sees.
var watch_spot: Vector2 = Vector2.INF
var watching: int = EcsWorld.NO_ENTITY
## Seconds until fleeing may mark ponds feared again.
var fear_left: float = 0.0
## Its own constant answers, re-asked every second or so: does it drink, what it eats, the
## cover kinds it hides in, its type.
var drinks: bool = false
var eats: StringName = &""
var hide_kinds: Array[StringName] = []
var kind: StringName = &""
## Seconds until those are asked again.
var profile_left: float = 0.0

func key() -> StringName:
	return &"memory"

func describe() -> Dictionary:
	var lines := {}
	for about in facts:
		var fact := facts[about] as EcsMemoryFact
		var strength := EcsMemoryFact.strength_of(fact, self)
		if strength <= 0.0:
			continue
		var names: PackedStringArray = []
		for bit in KIND_NAMES:
			if fact.kinds & bit != 0:
				names.append(KIND_NAMES[bit])
		var what := ", ".join(names)
		var text := "%d%%, place unknown" % roundi(strength * 100.0)
		if fact.placed:
			text = "%d%% at (%d, %d)" % [roundi(strength * 100.0),
				roundi(fact.position.x), roundi(fact.position.y)]
			var spread := EcsMemoryFact.spread_of(fact, self)
			if spread > 0.0:
				text += " ±%d" % roundi(spread)
		var fear := EcsMemoryFact.fear_of(fact, self)
		if fear > 0.0:
			text += ", fear %d%%" % roundi(fear * 100.0)
		var traffic := EcsMemoryFact.traffic_of(fact, self)
		if traffic > 0.0:
			text += ", traffic %.1f" % traffic
		lines["#%d %s" % [about, what]] = text
	return {"tab": &"own", "lines": lines}
