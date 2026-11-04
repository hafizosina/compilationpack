extends Node

## Plays each demo map (defs/worlds/) in the real main scene and checks that the
## concept it was built to show happens. Run with --fixed-fps 60 so a minute of
## simulation takes seconds. Exit code 0 only if every check passes.

const MAIN := "res://9. EcsSystem/main.tscn"
## Physics frames between samples (0.5 s).
const SAMPLE := 30

var _main: Node
var _checks: int = 0
var _failures: int = 0

func _ready() -> void:
	_main = (load(MAIN) as PackedScene).instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await _needs()
	await _hunting()
	await _foraging()
	await _ecs_toggles()
	print("[demo] %d/%d checks passed" % [_checks - _failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)

## Needs and utility: the urgent need wins, starving beats tired, a ready pair breeds.
func _needs() -> void:
	var seen := await _play("demo_needs", 20.0)
	_check("needs: the thirsty rabbit drinks", _max(seen, "rabbit_thirsty", "water") > 70.0)
	_check("needs: the hungry rabbit eats", _max(seen, "rabbit_hungry", "full") > 60.0)
	_check("needs: the rabbit that is both drinks first, its worse need",
		_first(seen, "rabbit_both", "water", 60.0) < _first(seen, "rabbit_both", "full", 60.0))
	_check("needs: the tired rabbit sleeps", _ever(seen, "rabbit_tired", "EcsAsleepFlag"))
	_check("needs: starving beats tired, it eats before it sleeps",
		_first(seen, "rabbit_starving", "full", 20.0) < _first_flag(seen, "rabbit_starving", "EcsAsleepFlag"))
	_check("needs: the ready pair has a baby", _most(seen, &"rabbit") > 7)

## Hunting by stats: one planner, two routes chosen by speed.
func _hunting() -> void:
	var seen := await _play("demo_hunting", 100.0)
	_check("hunting: the slow crocodile ambushes at the pond", _ever_state(seen, "croc_hungry", "AMBUSH"))
	_check("hunting: the fast dog chases instead", _ever_state(seen, "dog_hungry", "HUNT"))
	_check("hunting: the dog's pounce stuns", _ever(seen, "rabbit_in_open", "EcsStunnedFlag"))
	_check("hunting: the dog kills and eats", _died(seen, "rabbit_in_open")
		and _max(seen, "dog_hungry", "full") > 100.0)
	var kill := _died_at(seen, "rabbit_in_open")
	_check("hunting: the dog eats at the kill within 3 s, not after a walk back to cover",
		_value_at(seen, "dog_hungry", "full", kill + 3.0)
		> _value_at(seen, "dog_hungry", "full", kill - SAMPLE / 60.0))
	_check("hunting: the thirsty rabbit comes to drink and the crocodile takes it",
		_died(seen, "rabbit_thirsty") and _max(seen, "croc_hungry", "full") > 100.0)

## Carry vs graze: an inventory is one place reach can mean.
func _foraging() -> void:
	var seen := await _play("demo_foraging", 30.0)
	_check("foraging: a monkey fills its bag", _max(seen, "monkey_gatherer", "bag") >= 1.0
		or _max(seen, "monkey_hungry", "bag") >= 1.0)
	_check("foraging: and eats from it later", _max(seen, "monkey_hungry", "full") > 60.0)
	_check("foraging: the rabbit has no bag and eats where it stands",
		_max(seen, "rabbit_grazer", "bag") < 0.0 and _max(seen, "rabbit_grazer", "full") > 60.0)

## ECS toggles and the life cycle: a missing component is a missing behaviour.
func _ecs_toggles() -> void:
	var seen := await _play("demo_ecs_toggles", 70.0)
	_check("toggles: with hunger off, fullness never moves",
		_max(seen, "rabbit_no_hunger", "full") == 40.0 and _min(seen, "rabbit_no_hunger", "full") == 40.0)
	_check("toggles: with thirst off, hydration never moves",
		_max(seen, "rabbit_no_thirst", "water") == 40.0 and _min(seen, "rabbit_no_thirst", "water") == 40.0)
	_check("toggles: the normal rabbit eats and drinks",
		_max(seen, "rabbit_normal", "full") > 60.0 and _max(seen, "rabbit_normal", "water") > 60.0)
	_check("toggles: with no brain it never sets off anywhere, and starves",
		_max(seen, "rabbit_no_brain", "walking") == 0.0 and _died(seen, "rabbit_no_brain"))
	_check("toggles: a starved monkey leaves a corpse", _died(seen, "monkey_starving")
		and _ever_alive(seen, "corpse_of_monkey_starving"))
	_check("toggles: and the corpse rots away", _died(seen, "corpse_of_monkey_starving"))

# --- playing and sampling ---------------------------------------------------

## Builds `map`, plays `seconds`, and returns samples: name -> [{t, alive, ...}].
func _play(map: String, seconds: float) -> Dictionary:
	_main._on_new_world_requested(map)
	var seen: Dictionary = {}
	var frames := int(seconds * 60.0)
	for frame in frames + 1:
		if frame % SAMPLE == 0:
			_sample(seen, frame / 60.0)
		await get_tree().physics_frame
	return seen

func _sample(seen: Dictionary, t: float) -> void:
	var world: EcsWorld = _main._world
	var alive := {}
	var counts := {}
	for id in world.query([EcsNameComponent]):
		var named := world.get_component(id, EcsNameComponent) as EcsNameComponent
		var name := String(named.entity_name)
		counts[named.type_id] = int(counts.get(named.type_id, 0)) + 1
		alive[name] = true
		var row := {"t": t, "alive": true, "bag": -1.0}
		for component in world.components_of(id):
			if component is EcsHungerComponent:
				row["full"] = component.fullness
			elif component is EcsThirstComponent:
				row["water"] = component.hydration
			elif component is EcsMovementComponent:
				row["walking"] = 1.0 if component.has_destination else 0.0
			elif component is EcsInventoryComponent:
				row["bag"] = float(component.items.size())
			elif component is EcsFlag:
				row[String(component.get_script().get_global_name())] = true
		var brain := world.get_component(id, EcsLowBrainComponent) as EcsLowBrainComponent
		if brain != null:
			row["state"] = EcsLowBrainComponent.State.keys()[brain.state]
		if not seen.has(name):
			seen[name] = []
		seen[name].append(row)
	for name in seen:
		if not alive.has(name):
			seen[name].append({"t": t, "alive": false})
	seen["_counts"] = seen.get("_counts", []) + [counts]

func _rows(seen: Dictionary, name: String) -> Array:
	return seen.get(name, [])

func _max(seen: Dictionary, name: String, key: String) -> float:
	var best := -INF
	for row in _rows(seen, name):
		if row.has(key):
			best = maxf(best, float(row[key]))
	return best

func _min(seen: Dictionary, name: String, key: String) -> float:
	var least := INF
	for row in _rows(seen, name):
		if row.has(key):
			least = minf(least, float(row[key]))
	return least

## Seconds until `key` first rose above `above`, or INF.
func _first(seen: Dictionary, name: String, key: String, above: float) -> float:
	for row in _rows(seen, name):
		if row.has(key) and float(row[key]) > above:
			return row["t"]
	return INF

func _first_flag(seen: Dictionary, name: String, flag: String) -> float:
	for row in _rows(seen, name):
		if row.get(flag, false):
			return row["t"]
	return INF

func _ever(seen: Dictionary, name: String, flag: String) -> bool:
	return _first_flag(seen, name, flag) < INF

func _ever_state(seen: Dictionary, name: String, state: String) -> bool:
	return _rows(seen, name).any(func(row: Dictionary) -> bool: return row.get("state", "") == state)

func _ever_alive(seen: Dictionary, name: String) -> bool:
	return _rows(seen, name).any(func(row: Dictionary) -> bool: return row["alive"])

func _died(seen: Dictionary, name: String) -> bool:
	return _ever_alive(seen, name) and not _rows(seen, name).back()["alive"]

## Seconds at which `name` was first sampled dead, or INF.
func _died_at(seen: Dictionary, name: String) -> float:
	for row in _rows(seen, name):
		if not row["alive"]:
			return row["t"]
	return INF

## `key` at the last sample at or before `t`, or -INF.
func _value_at(seen: Dictionary, name: String, key: String, t: float) -> float:
	var found := -INF
	for row in _rows(seen, name):
		if row["t"] > t:
			break
		if row.has(key):
			found = float(row[key])
	return found

func _most(seen: Dictionary, type_id: StringName) -> int:
	var most := 0
	for counts in seen.get("_counts", []):
		most = maxi(most, int(counts.get(type_id, 0)))
	return most

func _check(what: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
	print("[demo] %s  %s" % ["PASS" if passed else "FAIL", what])
