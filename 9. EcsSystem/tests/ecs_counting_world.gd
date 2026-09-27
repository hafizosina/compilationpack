extends EcsWorld

## An EcsWorld that counts its own traffic, per pipeline stage, for the stress
## test's breakdown of where each stage's time goes.
##
## It times every `query()` directly — there are only a few per stage, so the
## clock's own cost is lost in the noise — and counts every `get_component`,
## `has` and `is_alive`, which are far too many and too cheap to time one by
## one. The stress test prices those counts with per-call costs it measures on
## a plain world in the same sitting.
##
## Counting slows every call a little, so this world is only used for a
## separate counting pass. The stage timings the report divides up come from a
## plain EcsWorld.

## The stage currently running; the stress test sets it before each system.
var stage: StringName = &""
## stage -> {"query_us", "queries", "ids", "get", "has", "alive"}
var counts: Dictionary = {}

func reset_counts() -> void:
	counts = {}

func _bucket() -> Dictionary:
	if not counts.has(stage):
		counts[stage] = {"query_us": 0.0, "queries": 0, "ids": 0, "get": 0, "has": 0, "alive": 0}
	return counts[stage]

func query(include: Array, exclude: Array = []) -> Array[int]:
	var began := Time.get_ticks_usec()
	var ids := super(include, exclude)
	var bucket := _bucket()
	bucket["query_us"] += float(Time.get_ticks_usec() - began)
	bucket["queries"] += 1
	bucket["ids"] += ids.size()
	return ids

func get_component(id: int, type: Script) -> EcsComponent:
	_bucket()["get"] += 1
	return super(id, type)

func has(id: int, type: Script) -> bool:
	_bucket()["has"] += 1
	return super(id, type)

func is_alive(id: int) -> bool:
	_bucket()["alive"] += 1
	return super(id)
