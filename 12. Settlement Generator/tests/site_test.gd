extends Node2D

## Headless test for module 12's step 2: the town's site and centre.
##
##   "$GODOT" --headless --path . "res://12. Settlement Generator/tests/site_test.tscn"
##
## Exits 0 only if every check passes. Prints how long picking a site takes.

const CATALOG := preload("res://10. Town Generator/defs/town_catalog.tres")
const ENTITIES := preload("res://10. Town Generator/defs/entity_catalog.tres")
const DEFS := "res://12. Settlement Generator/defs/settlements/%s.tres"
const REGION := "res://12. Settlement Generator/defs/lands/region.tres"
const TOWNS: Array[StringName] = [&"hamlet", &"village", &"town"]
const SEEDS: int = 10
const ZOOM: int = 8
## Small chunks, so the plaza always crosses several.
const CHUNK: int = 8

var _checks: int = 0
var _failures: int = 0
var _region: EcsLandDef
## Region plans by seed, and their blend shares.
var _plans: Dictionary = {}

func _ready() -> void:
	CATALOG.number()
	_region = load(REGION) as EcsLandDef
	_every_seed_and_size_gets_a_sound_town()
	_a_town_moved_by_hand()
	_the_centre_loads_through_the_build_system()
	_a_plaza_split_across_chunks_draws_as_one()
	print("[site] %d/%d checks passed" % [_checks - _failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)

func _plan(rng_seed: int) -> Dictionary:
	if not _plans.has(rng_seed):
		var plan := EcsTerrainGenerator.plan(_region, rng_seed, CATALOG, ENTITIES)
		_plans[rng_seed] = {"plan": plan, "shares": EcsTerrainGenerator.blend_shares(plan, _region)}
	return _plans[rng_seed]

func _pick(rng_seed: int, town: StringName) -> EcsSettlementSite:
	var p := _plan(rng_seed)
	return EcsSitePicker.pick(p["plan"], _region, load(DEFS % town), rng_seed, ZOOM, CATALOG, p["shares"])

## Every size of town over several seeds gets a site, and every site and centre is sound; the
## same seed gives the same town.
func _every_seed_and_size_gets_a_sound_town() -> void:
	for town in TOWNS:
		var def := load(DEFS % town) as EcsSettlementDef
		var first: Array[String] = []
		var usec := 0
		for s in SEEDS:
			var p := _plan(s)
			var started := Time.get_ticks_usec()
			var site := _pick(s, town)
			usec += Time.get_ticks_usec() - started
			var problems := EcsSiteCheck.problems(site, p["plan"], _region, def, s, ZOOM, p["shares"])
			if not problems.is_empty() and first.is_empty():
				first = problems
				first.push_front("seed %d:" % s)
		_check("%s: %d seeds, every town sound%s" % [town, SEEDS, "" if first.is_empty() else "  " + " ".join(first)], first.is_empty())
		print("[site]   %s: picking takes %d ms on average" % [town, usec / SEEDS / 1000])
	var a := _pick(3, &"village")
	var b := _pick(3, &"village")
	_check("the same seed gives the same site, plaza and commands", a.l2_cell == b.l2_cell and a.plaza == b.plaza
		and a.commands.size() == b.commands.size() and a.well == b.well)

## Moving the town by hand: onto water or too near the edge is refused with the reason; onto good
## land it is placed there.
func _a_town_moved_by_hand() -> void:
	var p := _plan(0)
	var kinds := (p["plan"] as Dictionary)["kinds"] as PackedByteArray
	var def := load(DEFS % &"village") as EcsSettlementDef
	var water := Vector2i(-1, -1)
	for i in kinds.size():
		var cell := Vector2i(i % _region.size.x, i / _region.size.x)
		if kinds[i] == EcsTerrainGenerator.WATER and Rect2i(Vector2i(40, 40), _region.size - Vector2i(80, 80)).has_point(cell):
			water = cell
			break
	var on_water := EcsSitePicker.place(p["plan"], _region, def, water, 0, ZOOM, CATALOG, p["shares"])
	var at_edge := EcsSitePicker.place(p["plan"], _region, def, Vector2i(2, 2), 0, ZOOM, CATALOG, p["shares"])
	_check("onto water is refused: %s" % on_water.get("refused", "accepted"), on_water.get("refused", "") == "on water")
	_check("by the region's edge is refused: %s" % at_edge.get("refused", "accepted"), String(at_edge.get("refused", "")).begins_with("too near"))
	var best := _pick(0, &"village")
	var moved := EcsSitePicker.place(p["plan"], _region, def, best.l2_cell, 0, ZOOM, CATALOG, p["shares"])
	_check("onto good land it is placed there", moved.has("site") and (moved["site"] as EcsSettlementSite).l2_cell == best.l2_cell)

## The town's area with its plaza and well and its nodes, through module 10's build system: every
## command accepted, stone on every plaza cell, the well born on its cell, no node on cleared ground.
func _the_centre_loads_through_the_build_system() -> void:
	var p := _plan(1)
	var def := load(DEFS % &"hamlet") as EcsSettlementDef
	var site := _pick(1, &"hamlet")
	var terrain := EcsTerrainGenerator.refine_terrain(p["plan"], _region, site.area.size, _region.child.shore_width, site.area.position,
		ZOOM, 1, 0, p["shares"])
	var blocked := PackedByteArray()
	blocked.resize(site.area.size.x * site.area.size.y)
	for rect in site.cleared:
		var part := rect.intersection(site.area)
		for y in range(part.position.y, part.end.y):
			for x in range(part.position.x, part.end.x):
				blocked[(y - site.area.position.y) * site.area.size.x + x - site.area.position.x] = 1
	for cell: Vector2i in site.cleared_cells:
		if site.area.has_point(cell):
			blocked[(cell.y - site.area.position.y) * site.area.size.x + cell.x - site.area.position.x] = 1
	var nodes := EcsTerrainGenerator.refine_nodes(_land(_region, site.area.size), terrain["zones"], 1, site.area.position, ENTITIES, blocked)
	var commands := EcsTerrainGenerator.terrain_commands(terrain["kinds"], site.area.size, Vector2i.ZERO, CATALOG)
	var whole: Array = []
	for node: Dictionary in nodes:
		commands.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, node["cell"], node["blueprint"], 0))
		whole.append({"cell": site.area.position + (node["cell"] as Vector2i), "size": node["size"]})
	# The town's commands on the area's cells; main roads and outlying works run on past it.
	commands.append_array(EcsTerrainChunks.clip(site, site.area, 0, true))
	var world := EcsWorld.new()
	var grid := EcsTownGrid.make(site.area.size.x, site.area.size.y, CATALOG.terrain_id(&"grass"))
	grid.commands.append_array(commands)
	world.add_singleton(grid)
	world.add_singleton(EcsLifecycleSingleton.new())
	var root := Node2D.new()
	add_child(root)
	var scheduler := EcsScheduler.new()
	scheduler.add(EcsLifecycleSystem.new(EcsEntityManager.new(root), ENTITIES)).add(EcsBuildCommandSystem.new(CATALOG, ENTITIES))
	for tick in 3:
		scheduler.run_all(world, 1.0 / 60.0)
	var accepted := commands.filter(func(c: EcsBuildCommand) -> bool: return c.result == &"ok").size()
	_check("all %d commands accepted by the build system" % commands.size(), accepted == commands.size())
	var stone := CATALOG.floor_id(def.plaza_floor)
	var floored := true
	for y in range(site.plaza.position.y, site.plaza.end.y):
		for x in range(site.plaza.position.x, site.plaza.end.x):
			if grid.floor[EcsTownGrid.index(grid, Vector2i(x, y) - site.area.position)] != stone:
				floored = false
	_check("stone covers every plaza cell", floored)
	var well := grid.object_id[EcsTownGrid.index(grid, site.well - site.area.position)]
	_check("the well is born on its cell", well > EcsWorld.NO_ENTITY and world.has(well, EcsGridPositionComponent))
	var problems := EcsSiteCheck.problems(site, p["plan"], _region, def, 1, ZOOM, p["shares"], whole)
	_check("no node on the cleared ground round the plaza (%d nodes planned)" % nodes.size(), problems.is_empty())
	root.free()

## The plaza drawn chunk by chunk: each chunk's floor, border included, is the town's floor on those
## cells, the well is placed by exactly one chunk, and no chunk plans a node on cleared ground.
func _a_plaza_split_across_chunks_draws_as_one() -> void:
	var p := _plan(2)
	var def := load(DEFS % &"town") as EcsSettlementDef
	var site := _pick(2, &"town")
	var chunks := EcsTerrainChunks.new(_region.size, ZOOM, CHUNK)
	chunks.site = site
	var floor_of: Dictionary = {}
	for command in site.commands:
		if command.kind == EcsBuildCommand.Kind.SET_FLOOR:
			floor_of[command.cell] = command.value
	var chunk_def := _land(_region, Vector2i(CHUNK, CHUNK))
	var under := chunks.touching(site.plaza)
	var same := true
	var wells := 0
	var nodes: Array = []
	for at in under:
		var outer := CHUNK + 2
		var floors := PackedInt32Array()
		floors.resize(outer * outer)
		for command in chunks.overlay(at, true):
			if command.kind == EcsBuildCommand.Kind.PLACE_OBJECT and command.blueprint == &"well":
				wells += 1
			elif command.kind == EcsBuildCommand.Kind.SET_FLOOR:
				floors[command.cell.y * outer + command.cell.x] = command.value
		for y in outer:
			for x in outer:
				var global := at * CHUNK + Vector2i(x, y) - Vector2i.ONE
				if floors[y * outer + x] != int(floor_of.get(global, 0)):
					same = false
		var terrain := EcsTerrainGenerator.refine_terrain(p["plan"], _region, Vector2i(CHUNK, CHUNK), _region.child.shore_width, at * CHUNK,
			ZOOM, 2, 1, p["shares"])
		for node: Dictionary in EcsTerrainGenerator.refine_nodes(chunk_def, terrain["zones"], 2, at, ENTITIES, chunks.blocked(at)):
			nodes.append({"cell": at * CHUNK + (node["cell"] as Vector2i), "size": node["size"]})
	_check("the plaza crosses %d chunks; each draws the town's floor on its cells and border" % under.size(), under.size() >= 4 and same)
	_check("the well is placed by exactly one chunk", wells == 1)
	var problems := EcsSiteCheck.problems(site, p["plan"], _region, def, 2, ZOOM, p["shares"], nodes)
	_check("no chunk plans a node on the cleared ground", problems.is_empty())

## The region's L1 land, `size` cells: what a town's area or a chunk grows.
func _land(region: EcsLandDef, size: Vector2i) -> EcsLandDef:
	var land := region.child.duplicate() as EcsLandDef
	land.size = size
	return land

func _check(what: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
	print("[site] %s  %s" % ["ok  " if passed else "FAIL", what])
