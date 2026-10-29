extends Node

## What fetching components costs, with nothing else in the way. Twenty
## skeleton systems, each asking for a random set of the module's real
## components, each walking every entity that has them: `query()`, then `has()`
## and `get_component()` per required type per entity, and no logic at all.
## Whatever a skeleton costs is the store's cost, so this is the floor every
## real system pays before it does any work.
##
## Run it:
##   GODOT="/home/zhenzhu/.local/share/Steam/steamapps/common/Godot Engine/godot.x11.opt.tools.64"
##   "$GODOT" --headless --path . "res://9. EcsSystem/tests/fetch_bench.tscn"
##   "$GODOT" --headless --path . "res://9. EcsSystem/tests/fetch_bench.tscn" -- --n=4000 --systems=20 --density=0.7 --seed=1
##
## Entities are not spawned through the manager — no blueprints, no nodes, just
## ids in an EcsWorld with components added directly — so physics, sprites and
## the scene tree cost nothing here. Each entity carries each component with
## probability `--density`, so a system asking for more types matches fewer
## entities, the way a real query narrows. The seed fixes both the world and
## each system's requirements, so two runs are the same question.
##
## Each system is timed four ways over the same ticks:
##   total — its run(): query, then has + get per required type per entity
##   query — query() alone
##   loop  — walking those ids and types with no call inside, the floor
##   has   — the has() calls alone, over the ids query returned, minus loop
##   get   — the get_component() calls alone, over the same ids, minus loop
##   rest  — total minus all four; near zero, and noise if it is not

## Every component type the module has. A skeleton picks its requirements from these.
var TYPES: Array[Script] = [
	EcsActionComponent, EcsBodyComponent, EcsConsumableComponent, EcsEnergyComponent,
	EcsHealthComponent, EcsHungerComponent, EcsInventoryComponent, EcsLowBrainComponent,
	EcsMovementComponent, EcsNameComponent, EcsPickableComponent, EcsPositionComponent,
	EcsSensorComponent, EcsSpawnerComponent, EcsSpriteComponent,
]
## Ticks run and thrown away before timing.
const WARMUP: int = 5
## Ticks averaged.
const SAMPLE: int = 30
## Fewest and most component types one skeleton asks for.
const MIN_REQUIRED: int = 1
const MAX_REQUIRED: int = 4

var N: int = 4000
var SYSTEMS: int = 20
var DENSITY: float = 0.7
var SEED: int = 1

## A system with no behaviour: the loop every real system opens with, and
## nothing after it.
class SkeletonSystem extends EcsSystem:
	var name: StringName
	var required: Array[Script] = []

	func label() -> StringName:
		return name

	func run(world: EcsWorld, _delta: float) -> void:
		for id in world.query(required):
			for type in required:
				if world.has(id, type):
					var _component := world.get_component(id, type)

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--n="):
			N = arg.substr(4).to_int()
		elif arg.begins_with("--systems="):
			SYSTEMS = arg.substr(10).to_int()
		elif arg.begins_with("--density="):
			DENSITY = arg.substr(10).to_float()
		elif arg.begins_with("--seed="):
			SEED = arg.substr(7).to_int()

	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var world := _populate(rng)
	var systems := _make_systems(rng)

	print("[fetch] %d entities, %d skeleton systems, density %.2f, seed %d, %d ticks averaged"
		% [N, SYSTEMS, DENSITY, SEED, SAMPLE])
	print("[fetch] times are ms per tick; us/ent is total over entities walked")
	print("[fetch] %-6s %-58s %6s %8s %8s %8s %8s %8s %8s %7s %7s"
		% ["system", "requires", "ents", "total", "query", "loop", "has", "get", "rest", "us/ent", "us/get"])

	var sums := {"total": 0.0, "query": 0.0, "loop": 0.0, "has": 0.0, "get": 0.0, "ents": 0, "gets": 0}
	for system in systems:
		var row := _time(world, system)
		var names := PackedStringArray()
		for type in system.required:
			names.append(type.get_global_name().trim_prefix("Ecs").trim_suffix("Component"))
		var ents: int = row["ents"]
		var gets: int = ents * system.required.size()
		var rest: float = row["total"] - row["query"] - row["loop"] - row["has"] - row["get"]
		print("[fetch] %-6s %-58s %6d %8.3f %8.3f %8.3f %8.3f %8.3f %8.3f %7.3f %7.3f"
			% [system.name, ", ".join(names), ents, row["total"], row["query"], row["loop"],
				row["has"], row["get"], rest,
				1000.0 * row["total"] / maxi(ents, 1),
				1000.0 * row["get"] / maxi(gets, 1)])
		for key in ["total", "query", "loop", "has", "get"]:
			sums[key] += row[key]
		sums["ents"] += ents
		sums["gets"] += gets

	var total: float = sums["total"]
	var rest_all: float = total - sums["query"] - sums["loop"] - sums["has"] - sums["get"]
	print("[fetch] %-6s %-58s %6d %8.3f %8.3f %8.3f %8.3f %8.3f %8.3f %7.3f %7.3f"
		% ["TOTAL", "", sums["ents"], total, sums["query"], sums["loop"], sums["has"], sums["get"],
			rest_all,
			1000.0 * total / maxi(sums["ents"], 1),
			1000.0 * sums["get"] / maxi(sums["gets"], 1)])
	print("[fetch] share of the total: query %.0f%%, loop %.0f%%, has %.0f%%, get %.0f%%, rest %.0f%%"
		% [100.0 * sums["query"] / total, 100.0 * sums["loop"] / total,
			100.0 * sums["has"] / total, 100.0 * sums["get"] / total, 100.0 * rest_all / total])
	print("[fetch] unit cost: has %.3f us, get_component %.3f us (loop removed)"
		% [1000.0 * sums["has"] / maxi(sums["gets"], 1), 1000.0 * sums["get"] / maxi(sums["gets"], 1)])
	_compare_gets(world, systems, sums["gets"])
	_compare_views(world, systems)
	get_tree().quit(0)

## Each skeleton whole, written the old way and through a cached view, so the
## number is what one bare-bones system costs per tick either way.
##
##   query+has+get — the skeleton's run(): query, then has and get per type
##   query+get     — the same without has, which query already answered
##   view, kept    — world.view() handing back the cached view, then reading
##                   every column; the tick nothing was born or died
##   view, rebuilt — the same with the cache emptied first, so view() runs the
##                   query and fills the columns; the tick something did
func _compare_views(world: EcsWorld, systems: Array[SkeletonSystem]) -> void:
	var views: Dictionary = world.get(&"_views")
	print("")
	print("[fetch] each system whole, ms per tick:")
	print("[fetch] %-6s %6s %14s %10s %11s %14s %8s"
		% ["system", "ents", "query+has+get", "query+get", "view, kept", "view, rebuilt", "kept vs"])
	var sums := [0.0, 0.0, 0.0, 0.0]
	var ents_all := 0
	for system in systems:
		var required: Array[Script] = system.required
		var ents := world.query(required).size()
		var row := [0.0, 0.0, 0.0, 0.0]

		var began := Time.get_ticks_usec()
		for i in SAMPLE:
			system.run(world, 0.0)
		row[0] = float(Time.get_ticks_usec() - began)

		began = Time.get_ticks_usec()
		for i in SAMPLE:
			for id in world.query(required):
				for type in required:
					var _c := world.get_component(id, type)
		row[1] = float(Time.get_ticks_usec() - began)

		world.view(required)
		began = Time.get_ticks_usec()
		for i in SAMPLE:
			var view := world.view(required)
			var columns: Array = []
			for type in required:
				columns.append(view.column(type))
			for k in view.ids.size():
				for column: Array in columns:
					var _c: EcsComponent = column[k]
		row[2] = float(Time.get_ticks_usec() - began)

		began = Time.get_ticks_usec()
		for i in SAMPLE:
			views.clear()
			var view := world.view(required)
			var columns: Array = []
			for type in required:
				columns.append(view.column(type))
			for k in view.ids.size():
				for column: Array in columns:
					var _c: EcsComponent = column[k]
		row[3] = float(Time.get_ticks_usec() - began)

		for c in 4:
			row[c] = row[c] / SAMPLE / 1000.0
			sums[c] += row[c]
		ents_all += ents
		print("[fetch] %-6s %6d %14.3f %10.3f %11.3f %14.3f %7.0f%%"
			% [system.name, ents, row[0], row[1], row[2], row[3], 100.0 * row[2] / row[0]])
	print("[fetch] %-6s %6d %14.3f %10.3f %11.3f %14.3f %7.0f%%"
		% ["TOTAL", ents_all, sums[0], sums[1], sums[2], sums[3], 100.0 * sums[2] / sums[0]])
	print("[fetch] per entity walked: %.3f / %.3f / %.3f / %.3f us"
		% [1000.0 * sums[0] / ents_all, 1000.0 * sums[1] / ents_all,
			1000.0 * sums[2] / ents_all, 1000.0 * sums[3] / ents_all])

## The same gets every skeleton makes, fetched four ways, all twenty systems
## together. Each is timed over the ids its query returned, with a bare loop of
## the same shape subtracted, so what is left is the fetch alone.
##
##   world.get_component — what every system calls today
##   fixed get_component — the same two lookups without `_store.get(type, {})`,
##                         whose `{}` is built on every call whether it is
##                         needed or not
##   table once          — the system takes each type's table once per run
##                         and indexes it itself: one lookup per get, no call
##   gathered refs       — the references already sitting in arrays, as a
##                         cached view would hand them over; no lookup at all
##
## It reads EcsWorld's private `_store` to price the last three without
## changing EcsWorld first. A probe, not a pattern.
func _compare_gets(world: EcsWorld, systems: Array[SkeletonSystem], gets: int) -> void:
	var store: Dictionary = world.get(&"_store")
	var ids_of: Array = []
	var tables_of: Array = []
	var columns_of: Array = []
	for system in systems:
		var ids := world.query(system.required)
		ids_of.append(ids)
		var tables: Array[Dictionary] = []
		var columns: Array = []
		for type in system.required:
			var table: Dictionary = store[type]
			tables.append(table)
			var column: Array[EcsComponent] = []
			for id in ids:
				column.append(table[id])
			columns.append(column)
		tables_of.append(tables)
		columns_of.append(columns)

	var loop := 0.0
	var current := 0.0
	var fixed := 0.0
	var once := 0.0
	var index_loop := 0.0
	var gathered := 0.0
	for s in systems.size():
		var required: Array[Script] = systems[s].required
		var ids: Array[int] = ids_of[s]
		var columns: Array = columns_of[s]

		var began := Time.get_ticks_usec()
		for i in SAMPLE:
			for id in ids:
				for type in required:
					pass
		loop += Time.get_ticks_usec() - began

		began = Time.get_ticks_usec()
		for i in SAMPLE:
			for id in ids:
				for type in required:
					var _c := world.get_component(id, type)
		current += Time.get_ticks_usec() - began

		began = Time.get_ticks_usec()
		for i in SAMPLE:
			for id in ids:
				for type in required:
					var _c := _fixed_get(store, id, type)
		fixed += Time.get_ticks_usec() - began

		began = Time.get_ticks_usec()
		for i in SAMPLE:
			var tables: Array[Dictionary] = []
			for type in required:
				tables.append(store[type])
			for id in ids:
				for table in tables:
					var _c: EcsComponent = table[id]
		once += Time.get_ticks_usec() - began

		var count := ids.size()
		began = Time.get_ticks_usec()
		for i in SAMPLE:
			for k in count:
				for column: Array[EcsComponent] in columns:
					pass
		index_loop += Time.get_ticks_usec() - began

		began = Time.get_ticks_usec()
		for i in SAMPLE:
			for k in count:
				for column: Array[EcsComponent] in columns:
					var _c := column[k]
		gathered += Time.get_ticks_usec() - began

	var rows := [
		["world.get_component", current - loop],
		["fixed get_component", fixed - loop],
		["table once", once - loop],
		["gathered refs", gathered - index_loop],
	]
	var base: float = rows[0][1]
	print("")
	print("[fetch] the same %d gets per tick, fetched four ways (loop removed):" % gets)
	print("[fetch] %-22s %10s %10s %10s" % ["how", "ms/tick", "us/get", "vs today"])
	for row in rows:
		var us: float = row[1] / SAMPLE
		print("[fetch] %-22s %10.3f %10.3f %9.0f%%"
			% [row[0], us / 1000.0, us / maxi(gets, 1), 100.0 * row[1] / base])

## get_component as it would read without the throwaway `{}`.
func _fixed_get(store: Dictionary, id: int, type: Script) -> EcsComponent:
	var table = store.get(type)
	if table == null:
		return null
	return (table as Dictionary).get(id)

## N entities, each carrying each component type with probability DENSITY. At
## least one, so no entity is an id with nothing filed against it.
func _populate(rng: RandomNumberGenerator) -> EcsWorld:
	var world := EcsWorld.new()
	for i in N:
		var id := world.create_entity()
		var added := 0
		for type in TYPES:
			if rng.randf() < DENSITY:
				world.add(id, type.new() as EcsComponent)
				added += 1
		if added == 0:
			world.add(id, TYPES[rng.randi_range(0, TYPES.size() - 1)].new() as EcsComponent)
	return world

## SYSTEMS skeletons, each requiring MIN_REQUIRED..MAX_REQUIRED distinct types.
func _make_systems(rng: RandomNumberGenerator) -> Array[SkeletonSystem]:
	var made: Array[SkeletonSystem] = []
	for s in SYSTEMS:
		var system := SkeletonSystem.new()
		system.name = StringName("s%02d" % (s + 1))
		var pool := TYPES.duplicate()
		for k in rng.randi_range(MIN_REQUIRED, MAX_REQUIRED):
			system.required.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
		made.append(system)
	return made

## One system, timed whole and then in parts, each averaged over SAMPLE ticks.
## The parts walk the same ids the query returns, so has and get are priced on
## exactly the calls run() makes.
func _time(world: EcsWorld, system: SkeletonSystem) -> Dictionary:
	for i in WARMUP:
		system.run(world, 0.0)
	var required := system.required
	var ids := world.query(required)

	var began := Time.get_ticks_usec()
	for i in SAMPLE:
		system.run(world, 0.0)
	var total := float(Time.get_ticks_usec() - began)

	began = Time.get_ticks_usec()
	for i in SAMPLE:
		var _ids := world.query(required)
	var query := float(Time.get_ticks_usec() - began)

	began = Time.get_ticks_usec()
	for i in SAMPLE:
		for id in ids:
			for type in required:
				pass
	var loop := float(Time.get_ticks_usec() - began)

	began = Time.get_ticks_usec()
	for i in SAMPLE:
		for id in ids:
			for type in required:
				var _yes := world.has(id, type)
	var has := float(Time.get_ticks_usec() - began)

	began = Time.get_ticks_usec()
	for i in SAMPLE:
		for id in ids:
			for type in required:
				var _component := world.get_component(id, type)
	var get := float(Time.get_ticks_usec() - began)

	return {
		"ents": ids.size(),
		"total": total / SAMPLE / 1000.0,
		"query": query / SAMPLE / 1000.0,
		"loop": loop / SAMPLE / 1000.0,
		"has": (has - loop) / SAMPLE / 1000.0,
		"get": (get - loop) / SAMPLE / 1000.0,
	}
