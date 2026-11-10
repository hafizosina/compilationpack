extends Node2D

## Headless test for module 12's step 4: plots, then the lanes they need.
##
##   "$GODOT" --headless --path . "res://12. Settlement Generator/tests/plot_test.tscn"
##
## Exits 0 only if every check passes. Prints how long a town with its plots takes.

const CATALOG := preload("res://10. Town Generator/defs/town_catalog.tres")
const ENTITIES := preload("res://10. Town Generator/defs/entity_catalog.tres")
const DEFS := "res://12. Settlement Generator/defs/settlements/%s.tres"
const TOWNS: Array[StringName] = [&"hamlet", &"village", &"town"]
const SEEDS: int = 6
const ZOOM: int = 8

var _checks: int = 0
var _failures: int = 0
var _plans: Dictionary = {}

func _ready() -> void:
	CATALOG.number()
	_every_town_gets_sound_plots()
	_the_same_seed_gives_the_same_plots()
	_plots_load_through_the_build_system()
	print("[plot] %d/%d checks passed" % [_checks - _failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)

func _region() -> EcsSettlementDef:
	return load(DEFS % &"region") as EcsSettlementDef

func _plan(region: EcsSettlementDef, rng_seed: int) -> Dictionary:
	if not _plans.has(rng_seed):
		var plan := EcsTerrainGenerator.plan(region, rng_seed, CATALOG, ENTITIES)
		_plans[rng_seed] = {"plan": plan, "shares": EcsTerrainGenerator.blend_shares(plan, region)}
	return _plans[rng_seed]

func _pick(region: EcsSettlementDef, rng_seed: int, town: StringName) -> EcsSettlementSite:
	var p := _plan(region, rng_seed)
	return EcsSitePicker.pick(p["plan"], region, load(DEFS % town), rng_seed, ZOOM, CATALOG, p["shares"])

## Every town size over several seeds: plots sound, every door on a road, roads still one network
## joined to the plaza, and most of the plots wanted placed.
func _every_town_gets_sound_plots() -> void:
	var region := _region()
	for town in TOWNS:
		var def := load(DEFS % town) as EcsSettlementDef
		var first: Array[String] = []
		var usec := 0
		var plots := 0
		var lanes := 0
		var laned := 0
		for s in SEEDS:
			var started := Time.get_ticks_usec()
			var site := _pick(region, s, town)
			usec += Time.get_ticks_usec() - started
			var p := _plan(region, s)
			var problems := EcsPlotCheck.problems(site, p["plan"], region, def, s, ZOOM, p["shares"])
			problems.append_array(EcsRoadCheck.problems(site, p["plan"], region, def, s, ZOOM, p["shares"]))
			plots += site.plots.size()
			lanes += site.roads.filter(func(r: Dictionary) -> bool: return r["kind"] == &"lane").size()
			laned += site.plots.filter(func(plot: Dictionary) -> bool:
				return site.road_cells.get(plot["door"] + plot["front"], &"") == &"lane").size()
			if not problems.is_empty() and first.is_empty():
				first = problems
				first.push_front("seed %d:" % s)
		var wanted := SEEDS * def.plots.x
		_check("%s: %d seeds, %d plots (%d at least wanted), %d lanes for %d doors on lanes, all sound%s" % [town, SEEDS,
			plots, wanted, lanes, laned, "" if first.is_empty() else "  " + " ".join(first)],
			first.is_empty() and plots >= wanted * 0.8 and lanes > 0)
		print("[plot]   %s: a town with its roads and plots takes %d ms on average" % [town, usec / SEEDS / 1000])

func _the_same_seed_gives_the_same_plots() -> void:
	var a := _pick(_region(), 1, &"village")
	var b := _pick(_region(), 1, &"village")
	var same := a.plots.size() == b.plots.size() and a.road_cells.size() == b.road_cells.size()
	for k in mini(a.plots.size(), b.plots.size()):
		same = same and a.plots[k]["footprint"] == b.plots[k]["footprint"] and a.plots[k]["door"] == b.plots[k]["door"]
	_check("the same seed gives the same plots and lanes (%d plots)" % a.plots.size(), same)

## A hamlet's area with plaza, roads, plots and nodes through module 10's build system: every command
## accepted, the road floor on every lane, and no node on a footprint or yard.
func _plots_load_through_the_build_system() -> void:
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
	var on_plot := 0
	for node: Dictionary in nodes:
		commands.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, node["cell"], node["blueprint"], 0))
		var rect := Rect2i(area.position + (node["cell"] as Vector2i), node["size"])
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				on_plot += 1 if site.plot_at.has(Vector2i(x, y)) else 0
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
	_check("all %d commands of the hamlet's area accepted by the build system" % commands.size(), accepted == commands.size())
	var road := CATALOG.floor_id(def.road_floor)
	var lanes := 0
	var floored := true
	for cell: Vector2i in site.road_cells:
		if site.road_cells[cell] == &"lane":
			lanes += 1
			floored = floored and grid.floor[EcsTownGrid.index(grid, cell - area.position)] == road
	_check("every one of %d lane cells has the road floor" % lanes, floored and lanes > 0)
	_check("no node on a footprint or yard (%d plots, %d nodes planned)" % [site.plots.size(), nodes.size()], on_plot == 0)
	root.free()

func _check(what: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
	print("[plot] %s  %s" % ["ok  " if passed else "FAIL", what])
