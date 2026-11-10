extends Node2D

## Headless test for module 12's step 3: the town's roads.
##
##   "$GODOT" --headless --path . "res://12. Settlement Generator/tests/road_test.tscn"
##
## Exits 0 only if every check passes. Prints how long planning a town with its roads takes.

const CATALOG := preload("res://10. Town Generator/defs/town_catalog.tres")
const ENTITIES := preload("res://10. Town Generator/defs/entity_catalog.tres")
const DEFS := "res://12. Settlement Generator/defs/settlements/%s.tres"
const TOWNS: Array[StringName] = [&"hamlet", &"village", &"town"]
const SEEDS: int = 6
const ZOOM: int = 8
const CHUNK: int = 32

var _checks: int = 0
var _failures: int = 0
var _plans: Dictionary = {}

func _ready() -> void:
	CATALOG.number()
	_every_town_gets_sound_roads()
	_main_roads_share_a_trunk()
	_a_river_crossing_is_a_walkable_bridge()
	_roads_load_through_the_build_system()
	_roads_draw_the_same_across_chunks()
	print("[road] %d/%d checks passed" % [_checks - _failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)

func _region(water: int = -1) -> EcsSettlementDef:
	var def := (load(DEFS % &"region") as EcsSettlementDef).duplicate() as EcsSettlementDef
	if water >= 0:
		def.water = water
		def.water_share = 0.15
	return def

func _plan(region: EcsSettlementDef, rng_seed: int) -> Dictionary:
	var key := [region.water, rng_seed]
	if not _plans.has(key):
		var plan := EcsTerrainGenerator.plan(region, rng_seed, CATALOG, ENTITIES)
		_plans[key] = {"plan": plan, "shares": EcsTerrainGenerator.blend_shares(plan, region)}
	return _plans[key]

func _pick(region: EcsSettlementDef, rng_seed: int, town: StringName) -> EcsSettlementSite:
	var p := _plan(region, rng_seed)
	return EcsSitePicker.pick(p["plan"], region, load(DEFS % town), rng_seed, ZOOM, CATALOG, p["shares"])

## Every town size over several seeds, and a coast-only region, has sound roads: main roads from
## the site to the edge, lanes in the area, all joined, bridged only on water and few times.
func _every_town_gets_sound_roads() -> void:
	var region := _region()
	for town in TOWNS:
		var def := load(DEFS % town) as EcsSettlementDef
		var first: Array[String] = []
		var usec := 0
		var lanes := 0
		for s in SEEDS:
			var started := Time.get_ticks_usec()
			var site := _pick(region, s, town)
			usec += Time.get_ticks_usec() - started
			var p := _plan(region, s)
			var problems := EcsRoadCheck.problems(site, p["plan"], region, def, s, ZOOM, p["shares"])
			lanes += site.roads.filter(func(r: Dictionary) -> bool: return r["kind"] == &"lane").size() if site != null else 0
			if not problems.is_empty() and first.is_empty():
				first = problems
				first.push_front("seed %d:" % s)
		_check("%s: %d seeds, every town's roads sound, %d lanes in all%s" % [town, SEEDS, lanes,
			"" if first.is_empty() else "  " + " ".join(first)], first.is_empty() and lanes > SEEDS)
		print("[road]   %s: a town with its roads takes %d ms on average" % [town, usec / SEEDS / 1000])
	var coast := _region(EcsSettlementDef.Water.COAST)
	var site := _pick(coast, 3, &"village")
	var p := _plan(coast, 3)
	var problems := EcsRoadCheck.problems(site, p["plan"], coast, load(DEFS % &"village"), 3, ZOOM, p["shares"])
	_check("on a coast-only region the sea's side has no exit, and the roads are sound%s" % ("" if problems.is_empty() else "  " + " ".join(problems)),
		problems.is_empty() and site.exits.all(func(e: Vector2i) -> bool:
			return ((p["plan"] as Dictionary)["kinds"] as PackedByteArray)[e.y * coast.size.x + e.x] != EcsTerrainGenerator.WATER))
	var again := _pick(_region(), 1, &"village")
	var first_site := _pick(_region(), 1, &"village")
	_check("the same seed gives the same roads", again.road_cells.size() == first_site.road_cells.size() and again.exits == first_site.exits)

## Two exits on the same side share a trunk out of town: their L2 routes overlap.
func _main_roads_share_a_trunk() -> void:
	var region := _region()
	var best := 0
	for s in SEEDS:
		for town in TOWNS:
			var site := _pick(region, s, town)
			var mains := site.roads.filter(func(r: Dictionary) -> bool: return r["kind"] == &"main")
			for a in mains.size():
				for b in range(a + 1, mains.size()):
					best = maxi(best, _shared(mains[a]["l2_points"], mains[b]["l2_points"]))
	_check("main roads share a trunk before forking: up to %d region cells shared" % best, best >= 5)

func _shared(a: PackedVector2Array, b: PackedVector2Array) -> int:
	var cells: Dictionary = {}
	for p in a:
		cells[Vector2i(p.round())] = true
	var shared: Dictionary = {}
	for p in b:
		if cells.has(Vector2i(p.round())):
			shared[Vector2i(p.round())] = true
	return shared.size()

## A main road over the river is a bridge of the bridge floor, and module 10's nav walks it.
func _a_river_crossing_is_a_walkable_bridge() -> void:
	var region := _region()
	var site: EcsSettlementSite = null
	var rng_seed := 0
	for s in SEEDS:
		var candidate := _pick(region, s, &"village")
		if candidate.bridges > 0:
			site = candidate
			rng_seed = s
			break
	if site == null:
		_check("a seed with a bridge", false)
		return
	var bridge := Vector2i.ZERO
	for cell: Vector2i in site.road_cells:
		if site.road_cells[cell] == &"bridge":
			bridge = cell
			break
	var chunks := EcsTerrainChunks.new(region.size, ZOOM, CHUNK)
	chunks.site = site
	var at := chunks.chunk_at(bridge)
	var level := _chunk_world(region, rng_seed, chunks, at)
	var grid := level["grid"] as EcsTownGridSingleton
	var local := bridge - at * CHUNK + Vector2i.ONE
	var i := EcsTownGrid.index(grid, local)
	var nav := (level["world"] as EcsWorld).get_singleton(EcsTownNavSingleton) as EcsTownNavSingleton
	_check("the bridge cell at %s is water under a %s floor, and walkable" % [bridge, (load(DEFS % &"village") as EcsSettlementDef).bridge_floor],
		grid.terrain[i] == CATALOG.terrain_id(&"water") and grid.floor[i] == CATALOG.floor_id(&"wood") and EcsTownNavSystem.walkable(nav, local))

## A chunk's world with its terrain and the town's overlay, through module 10's pipeline.
func _chunk_world(region: EcsSettlementDef, rng_seed: int, chunks: EcsTerrainChunks, at: Vector2i) -> Dictionary:
	var p := _plan(region, rng_seed)
	var terrain := EcsTerrainGenerator.refine_terrain(p["plan"], region, Vector2i(CHUNK, CHUNK), 2, at * CHUNK, ZOOM, rng_seed, 1, p["shares"])
	var outer := Vector2i(CHUNK + 2, CHUNK + 2)
	var commands := EcsTerrainGenerator.terrain_commands(terrain["kinds"], outer, Vector2i.ZERO, CATALOG)
	commands.append_array(chunks.overlay(at, true))
	var world := EcsWorld.new()
	var grid := EcsTownGrid.make(outer.x, outer.y, CATALOG.terrain_id(&"grass"))
	grid.commands.append_array(commands)
	world.add_singleton(grid)
	world.add_singleton(EcsLifecycleSingleton.new())
	world.add_singleton(EcsTownNavSingleton.new())
	var root := Node2D.new()
	add_child(root)
	var scheduler := EcsScheduler.new()
	scheduler.add(EcsLifecycleSystem.new(EcsEntityManager.new(root), ENTITIES)).add(EcsBuildCommandSystem.new(CATALOG, ENTITIES)) \
		.add(EcsTownNavSystem.new(CATALOG))
	for tick in 3:
		scheduler.run_all(world, 1.0 / 60.0)
	root.queue_free()
	return {"world": world, "grid": grid, "commands": commands}

## The town's area with plaza, roads, lanes and its nodes, through module 10's build system: every
## command accepted, the road floor on every road cell in the area, no node on a road or verge.
func _roads_load_through_the_build_system() -> void:
	var region := _region()
	var p := _plan(region, 2)
	var def := load(DEFS % &"hamlet") as EcsSettlementDef
	var site := _pick(region, 2, &"hamlet")
	var area := site.area
	var terrain := EcsTerrainGenerator.refine_terrain(p["plan"], region, area.size, def.shore_width, area.position, ZOOM, 2, 0, p["shares"])
	var blocked := PackedByteArray()
	blocked.resize(area.size.x * area.size.y)
	for rect in site.cleared:
		var part := rect.intersection(area)
		for y in range(part.position.y, part.end.y):
			for x in range(part.position.x, part.end.x):
				blocked[(y - area.position.y) * area.size.x + x - area.position.x] = 1
	for cell: Vector2i in site.cleared_cells:
		if area.has_point(cell):
			blocked[(cell.y - area.position.y) * area.size.x + cell.x - area.position.x] = 1
	var nodes := EcsTerrainGenerator.refine_nodes(def, terrain["zones"], 2, area.position, ENTITIES, blocked)
	var commands := EcsTerrainGenerator.terrain_commands(terrain["kinds"], area.size, Vector2i.ZERO, CATALOG)
	var whole: Array = []
	for node: Dictionary in nodes:
		commands.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, node["cell"], node["blueprint"], 0))
		whole.append({"cell": area.position + (node["cell"] as Vector2i), "size": node["size"]})
	for command in site.commands:
		if not area.has_point(command.cell):
			continue
		var local := command.cell - area.position
		commands.append(EcsBuildCommand.place(command.kind, local, command.blueprint, command.value) if command.kind == EcsBuildCommand.Kind.PLACE_OBJECT
			else EcsBuildCommand.make(command.kind, local, command.value))
	var world := EcsWorld.new()
	var grid := EcsTownGrid.make(area.size.x, area.size.y, CATALOG.terrain_id(&"grass"))
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
	_check("all %d commands of the town's area accepted by the build system" % commands.size(), accepted == commands.size())
	var road := CATALOG.floor_id(def.road_floor)
	var bridge := CATALOG.floor_id(def.bridge_floor)
	var floored := true
	for cell: Vector2i in site.road_cells:
		if area.has_point(cell):
			var want := bridge if site.road_cells[cell] == &"bridge" else road
			if grid.floor[EcsTownGrid.index(grid, cell - area.position)] != want:
				floored = false
	_check("every road cell in the area has its floor", floored)
	var problems := EcsRoadCheck.problems(site, p["plan"], region, def, 2, ZOOM, p["shares"], whole)
	_check("no node on a road or its verge (%d nodes planned)" % nodes.size(), problems.is_empty())
	root.free()

## Chunks the roads cross draw the town's floors on their cells and border, as the town has them.
func _roads_draw_the_same_across_chunks() -> void:
	var region := _region()
	var site := _pick(region, 0, &"village")
	var chunks := EcsTerrainChunks.new(region.size, ZOOM, CHUNK)
	chunks.site = site
	var floor_of: Dictionary = {}
	for command in site.commands:
		if command.kind == EcsBuildCommand.Kind.SET_FLOOR:
			floor_of[command.cell] = command.value
	var under: Dictionary = {}
	for cell: Vector2i in site.road_cells:
		under[chunks.chunk_at(cell)] = true
	var same := true
	for at: Vector2i in under:
		var outer := CHUNK + 2
		var floors := PackedInt32Array()
		floors.resize(outer * outer)
		for command in chunks.overlay(at, false):
			floors[command.cell.y * outer + command.cell.x] = command.value
		for y in outer:
			for x in outer:
				if floors[y * outer + x] != int(floor_of.get(at * CHUNK + Vector2i(x, y) - Vector2i.ONE, 0)):
					same = false
	_check("the roads cross %d chunks; each draws the town's floors on its cells and border" % under.size(), under.size() > 20 and same)

func _check(what: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
	print("[road] %s  %s" % ["ok  " if passed else "FAIL", what])
