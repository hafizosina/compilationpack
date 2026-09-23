extends Node2D

## How many entities module 9 carries before a tick costs more than it can
## afford. Ramps the population, runs the real pipeline over it, and reports the
## per-tick cost and the frame rate that implies.
##
## Run it:
##   GODOT="/home/zhenzhu/.local/share/Steam/steamapps/common/Godot Engine/godot.x11.opt.tools.64"
##   "$GODOT" --headless --path . "res://9. EcsSystem/tests/stress_test.tscn"
##
## **It measures the simulation, not the frame.** Headless draws nothing, so
## these numbers are the scheduler's cost alone: the entity count at which the
## *sim* can no longer keep up. A windowed run also pays for drawing the
## sprites, so the real frame rate at any of these counts is lower, never
## higher.
##
## Entities are laid out on a jittered grid at a fixed spacing rather than
## scattered in a fixed arena. Crowding, not population, is what makes collision
## and perception expensive — pack 6400 entities into the shipped arena and the
## answer says more about the stacking than about the system. Fixed spacing
## keeps each entity's neighbourhood the same size as the population grows, so
## the curve below is the cost of *more entities*, which is the question.

## The delta handed to every system, matching a 60 Hz physics step.
const TICK: float = 1.0 / 60.0
## Population steps. The ramp stops as soon as a tick crosses the budget.
const SIZES: Array[int] = [100, 200, 400, 800, 1600, 3200, 4000, 4400, 4600, 4800]
## Pixels between entities. Above the largest body (36) so nothing is born
## permanently overlapping, below the smallest sensor (280) so everything has
## neighbours to perceive.
const SPACING: float = 90.0
## Ticks thrown away before measuring — the first few build the physics state.
const WARMUP: int = 12
## Ticks averaged.
const SAMPLE: int = 30
## 4 FPS. The question is where a tick costs more than this.
const BUDGET_MS: float = 250.0

var _world: EcsWorld
var _manager: EcsEntityManager
var _systems: Array[EcsSystem] = []
var _entities: Node2D
var _catalog: EcsEntityCatalog

func _ready() -> void:
	_catalog = load("res://9. EcsSystem/defs/catalog.tres") as EcsEntityCatalog
	_entities = Node2D.new()
	_entities.name = "Entities"
	add_child(_entities)
	_manager = EcsEntityManager.new(_entities)

	print("[stress] budget %.0f ms/tick (%.0f FPS). simulation only, nothing is drawn."
		% [BUDGET_MS, 1000.0 / BUDGET_MS])
	print("[stress] %6s %9s %9s %9s %8s" % ["n", "spawn ms", "tick ms", "per ent", "FPS"])

	var last_ok := 0
	var first_over := 0
	var worst: Dictionary = {}
	var every: Array[Dictionary] = []
	for n in SIZES:
		var result := await _measure(n)
		var tick_ms: float = result["tick_ms"]
		print("[stress] %6d %9.0f %9.2f %9.4f %8.1f"
			% [n, result["spawn_ms"], tick_ms, tick_ms / n, 1000.0 / tick_ms])
		worst = result
		every.append(result)
		if tick_ms >= BUDGET_MS:
			first_over = n
			break
		last_ok = n

	print("")
	if first_over == 0:
		print("[stress] never reached %.0f ms — %d entities still ran at %.1f FPS."
			% [BUDGET_MS, last_ok, 1000.0 / float(worst["tick_ms"])])
	else:
		print("[stress] %d entities is the last step under budget; %d crosses it."
			% [last_ok, first_over])
	_report_matrix(every)
	_report_breakdown(worst)
	_probe_access(worst)
	get_tree().quit(0)

## Splits the per-entity floor into query, component fetch, and the actual work,
## using EcsMovementSystem as the probe because it is the purest per-entity
## stage in the pipeline: two components in, one position out, no neighbours.
##
## This exists to put a number on HANDOFF.md §8's data-structure argument.
## Dictionary-of-dictionaries pays for `query()` building an id list and then two
## hashed `get_component` lookups per entity; archetype or packed-array storage
## would replace both with walking arrays that are already in the right order.
## The fourth measurement is that ceiling: the identical arithmetic over
## pre-gathered component references, which is what "the fetch is free" would
## cost.
func _probe_access(result: Dictionary) -> void:
	if result.is_empty():
		return
	var n: int = result["n"]
	var rounds := 20
	var began: int = 0

	var query_us: float = 0.0
	for i in rounds:
		began = Time.get_ticks_usec()
		var ids := _world.query([EcsPositionComponent, EcsMovementComponent])
		query_us += float(Time.get_ticks_usec() - began)
		if ids.is_empty():
			return

	var fetch_us: float = 0.0
	for i in rounds:
		began = Time.get_ticks_usec()
		var sink: float = 0.0
		for id in _world.query([EcsPositionComponent, EcsMovementComponent]):
			var move := _world.get_component(id, EcsMovementComponent) as EcsMovementComponent
			var here := _world.get_component(id, EcsPositionComponent) as EcsPositionComponent
			sink += move.speed + here.position.x
		fetch_us += float(Time.get_ticks_usec() - began)

	# Gathered once, then walked — the shape archetype storage would hand a
	# system for free.
	var moves: Array[EcsMovementComponent] = []
	var places: Array[EcsPositionComponent] = []
	for id in _world.query([EcsPositionComponent, EcsMovementComponent]):
		moves.append(_world.get_component(id, EcsMovementComponent) as EcsMovementComponent)
		places.append(_world.get_component(id, EcsPositionComponent) as EcsPositionComponent)

	var packed_us: float = 0.0
	for i in rounds:
		began = Time.get_ticks_usec()
		for k in moves.size():
			var move := moves[k]
			if not move.has_destination:
				move.velocity = Vector2.ZERO
				continue
			var here := places[k]
			var to_go := move.destination - here.position
			var step := move.speed * TICK
			if to_go.length() <= maxf(step, move.arrive_radius):
				here.position = move.destination
				move.has_destination = false
				move.velocity = Vector2.ZERO
				move.time_left = 0.0
				continue
			# Mirrors the trip clock in EcsMovementSystem. It has to: this
			# block is only worth timing while it is the same arithmetic the
			# real stage does, and the moment it drifts the µs/entity below
			# stops being comparable to the stage above it.
			if move.time_left <= 0.0:
				move.time_left = to_go.length() / maxf(move.speed, 0.01) \
					* move.timeout_slack + move.timeout_grace
			move.time_left -= TICK
			if move.time_left <= 0.0:
				move.has_destination = false
				move.velocity = Vector2.ZERO
				move.time_left = 0.0
				continue
			move.velocity = to_go.normalized() * move.speed
			here.position += move.velocity * TICK
		packed_us += float(Time.get_ticks_usec() - began)

	var q := query_us / rounds / 1000.0
	var f := fetch_us / rounds / 1000.0
	var pk := packed_us / rounds / 1000.0
	var full: float = (result["systems"] as Dictionary).get(&"movement", 0.0)

	print("")
	print("[stress] where the per-entity floor goes, probed on movement at %d entities:" % n)
	print("[stress]   query() alone                    %7.2f ms   %6.3f us/entity" % [q, q * 1000.0 / n])
	print("[stress]   query + 2x get_component         %7.2f ms   %6.3f us/entity" % [f, f * 1000.0 / n])
	print("[stress]     ^ of which the fetch           %7.2f ms   %6.3f us/entity" % [f - q, (f - q) * 1000.0 / n])
	print("[stress]   the same maths, refs pre-gathered%7.2f ms   %6.3f us/entity" % [pk, pk * 1000.0 / n])
	print("[stress]   EcsMovementSystem as it runs     %7.2f ms   %6.3f us/entity" % [full, full * 1000.0 / n])
	if full > 0.0:
		print("[stress]   => access overhead is %.0f%% of the stage (%.2f of %.2f ms)"
			% [100.0 * (full - pk) / full, full - pk, full])

## Builds a world of `n`, lets it settle, then times the pipeline.
func _measure(n: int) -> Dictionary:
	_manager.clear()
	_world = EcsWorld.new()
	_world.add_singleton(EcsLifecycleComponent.new())
	_world.add_singleton(EcsSelectionComponent.new())
	_build_pipeline()

	var began := Time.get_ticks_usec()
	_populate(n)
	var spawn_ms := (Time.get_ticks_usec() - began) / 1000.0

	for i in WARMUP:
		_run_once()
		await get_tree().physics_frame

	var totals := PackedFloat64Array()
	totals.resize(_systems.size())
	var tick_total: float = 0.0
	for i in SAMPLE:
		var costs := _run_once()
		for s in _systems.size():
			totals[s] += costs[s]
			tick_total += costs[s]
		await get_tree().physics_frame

	var per_system: Dictionary = {}
	for s in _systems.size():
		per_system[_systems[s].label()] = totals[s] / SAMPLE / 1000.0
	return {
		"n": n,
		"spawn_ms": spawn_ms,
		"tick_ms": tick_total / SAMPLE / 1000.0,
		"systems": per_system,
		"work": _work_done(n),
	}

## What the pipeline actually chewed on this tick, so a stage's cost can be read
## per unit of work instead of per entity. Most stages here are not paying for
## the entity, they are paying for its neighbours.
func _work_done(n: int) -> Dictionary:
	var perceived: int = 0
	var reached: int = 0
	var bodies: int = 0
	var overlaps: int = 0
	for id in _world.query([EcsSensorComponent]):
		perceived += (_world.get_component(id, EcsSensorComponent) as EcsSensorComponent).perceived.size()
	for id in _world.query([EcsActionComponent]):
		reached += (_world.get_component(id, EcsActionComponent) as EcsActionComponent).reached.size()
	for id in _world.query([EcsPositionComponent, EcsBodyComponent]):
		bodies += 1
		var body := _manager.node_for(id, EcsConst.NODE_BODY) as Area2D
		if body != null:
			overlaps += body.get_overlapping_areas().size()
	return {
		"perceived": perceived, "reached": reached,
		"bodies": bodies, "overlaps": overlaps,
		"perceived_each": float(perceived) / n,
		"reached_each": float(reached) / n,
		"overlaps_each": float(overlaps) / maxi(bodies, 1),
	}

## The pipeline main.gd builds, in the same order. The two views it needs are
## real nodes but inert: the overlay is hidden, so EcsDebugSystem returns early
## exactly as it does with F1 off, which is how anyone measuring anything would
## be running.
func _build_pipeline() -> void:
	var overlay := EcsDebugOverlay.new()
	overlay.visible = false
	add_child(overlay)
	var marker := EcsSelectionMarker.new()
	add_child(marker)

	_systems = [
		EcsLifecycleSystem.new(_manager, _catalog),
		EcsSpawnerSystem.new(),
		EcsSensorSystem.new(_manager),
		EcsForageSystem.new(),
		EcsLowBrainSystem.new(),
		EcsMovementSystem.new(),
		EcsCollisionSystem.new(_manager),
		EcsPickupSystem.new(),
		EcsSelectionSystem.new(marker),
		EcsNodeSyncSystem.new(_manager),
		EcsDebugSystem.new(overlay),
		EcsCensusSystem.new(),
		EcsInspectSystem.new(),
	]

## One tick, timing each stage. Same call sequence as EcsScheduler.run_all —
## unrolled only so the cost can be attributed.
func _run_once() -> PackedFloat64Array:
	var costs := PackedFloat64Array()
	costs.resize(_systems.size())
	for s in _systems.size():
		var began := Time.get_ticks_usec()
		_systems[s].run(_world, TICK)
		costs[s] = float(Time.get_ticks_usec() - began)
	return costs

## A jittered grid of alternating rabbits and monkeys, with the wander bounds
## grown to match so nothing spends the run walking into a wall.
func _populate(n: int) -> void:
	var columns := int(ceil(sqrt(float(n))))
	var half := columns * SPACING * 0.5
	EcsConst.world_bounds = Rect2(-half, -half, half * 2.0, half * 2.0)
	for i in n:
		var spot := Vector2(
			(i % columns) * SPACING - half + randf_range(-18.0, 18.0),
			(i / columns) * SPACING - half + randf_range(-18.0, 18.0))
		_manager.spawn(_world, _catalog, &"rabbit" if i % 2 == 0 else &"monkey", spot)

## Every stage at every population, so the shape of each curve is visible
## rather than one snapshot at the crossing. The second table is the one that
## says something: a stage whose us/entity is flat costs what it costs, and a
## stage whose us/entity climbs is being paid for by something other than the
## entity — its neighbours.
const COLUMNS: Array[StringName] = [&"sensor", &"collision", &"node_sync", &"pickup",
	&"movement", &"forage", &"low_brain"]

func _report_matrix(every: Array[Dictionary]) -> void:
	if every.is_empty():
		return

	print("")
	print("[stress] per-stage ms, at each population")
	var header := "[stress] %6s" % "n"
	for name_key in COLUMNS:
		header += " %9s" % name_key
	print(header + " %9s %9s" % ["other", "TICK"])
	for result in every:
		var systems: Dictionary = result["systems"]
		var row := "[stress] %6d" % result["n"]
		var named: float = 0.0
		for name_key in COLUMNS:
			var ms: float = systems.get(name_key, 0.0)
			named += ms
			row += " %9.2f" % ms
		print(row + " %9.2f %9.2f" % [float(result["tick_ms"]) - named, result["tick_ms"]])

	print("")
	print("[stress] per-stage microseconds per entity, at each population")
	print(header + " %9s %9s" % ["other", "TICK"])
	for result in every:
		var systems: Dictionary = result["systems"]
		var n: int = result["n"]
		var row := "[stress] %6d" % n
		var named: float = 0.0
		for name_key in COLUMNS:
			var ms: float = systems.get(name_key, 0.0)
			named += ms
			row += " %9.3f" % (ms * 1000.0 / n)
		print(row + " %9.3f %9.3f"
			% [(float(result["tick_ms"]) - named) * 1000.0 / n,
			   float(result["tick_ms"]) * 1000.0 / n])

func _report_breakdown(result: Dictionary) -> void:
	if result.is_empty():
		return
	var n: int = result["n"]
	var systems: Dictionary = result["systems"]
	var order := systems.keys()
	order.sort_custom(func(a, b): return systems[a] > systems[b])
	print("[stress] where the time goes at %d entities:" % n)
	var summed: float = 0.0
	var quiet: float = 0.0
	for name_key in order:
		var ms: float = systems[name_key]
		summed += ms
		if ms < 0.01:
			quiet += ms
			continue
		print("[stress]   %-11s %8.2f ms  %5.1f%%  %7.4f ms/entity"
			% [name_key, ms, 100.0 * ms / float(result["tick_ms"]), ms / n])
	# Printed so a table copied out of this output can be checked against the
	# tick it claims to break down. A breakdown that does not add up is a
	# breakdown with a row from another run in it.
	print("[stress]   %-11s %8.2f ms  (stages below 0.01 ms, folded in)" % ["rest", quiet])
	print("[stress]   %-11s %8.2f ms  vs %.2f ms measured" % ["TOTAL", summed, result["tick_ms"]])

	var work: Dictionary = result["work"]
	print("")
	print("[stress] what the pipeline was actually chewing on, per tick at %d:" % n)
	print("[stress]   sensor areas returned %d ids total, %.1f per sensing entity"
		% [work["perceived"], work["perceived_each"]])
	print("[stress]   action areas returned %d ids total, %.1f per acting entity"
		% [work["reached"], work["reached_each"]])
	print("[stress]   body areas returned %d overlap pairs, %.1f per body"
		% [work["overlaps"], work["overlaps_each"]])
	var sensor_ms: float = systems.get(&"sensor", 0.0)
	var collision_ms: float = systems.get(&"collision", 0.0)
	var pickup_ms: float = systems.get(&"pickup", 0.0)
	var forage_ms: float = systems.get(&"forage", 0.0)
	var ids: int = maxi(work["perceived"] + work["reached"], 1)
	print("[stress]   => sensor    %6.3f us per id returned" % (sensor_ms * 1000.0 / ids))
	print("[stress]   => collision %6.3f us per overlap pair" % (collision_ms * 1000.0 / maxi(work["overlaps"], 1)))
	print("[stress]   => pickup    %6.3f us per id in reach" % (pickup_ms * 1000.0 / maxi(work["reached"], 1)))
	print("[stress]   => forage    %6.3f us per id perceived" % (forage_ms * 1000.0 / maxi(work["perceived"], 1)))
