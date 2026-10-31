class_name EcsMemoryComponent
extends EcsComponent

## Places it has seen and may walk back to. Only EcsMemorySystem writes it.

## Most facts kept; past this the weakest is forgotten.
@export var capacity: int = 32
## Seconds unseen before a fact fades out.
@export var remember_for: float = 180.0

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
		lines["#%d %s" % [about, kind]] = "%d%% at (%d, %d)" % [roundi(fact.strength * 100.0),
			roundi(fact.position.x), roundi(fact.position.y)]
	return {"tab": &"own", "lines": lines}
