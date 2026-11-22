extends Node2D

## Headless test for module 12's steps 4 and 5b: plots placed by role, then the lanes they need.
##
##   "$GODOT" --headless --path . "res://12. Settlement Generator/tests/plot_test.tscn"
##
## Exits 0 only if every check passes. Prints how long a town with its plots takes.

const CATALOG := preload("res://10. Town Generator/defs/town_catalog.tres")
const ENTITIES := preload("res://10. Town Generator/defs/entity_catalog.tres")
const DEFS := "res://12. Settlement Generator/defs/settlements/%s.tres"
const REGION := "res://12. Settlement Generator/defs/lands/region.tres"
const TOWNS: Array[StringName] = [&"hamlet", &"village", &"town"]
const SEEDS: int = 6
const ZOOM: int = 8

var _checks: int = 0
var _failures: int = 0
var _plans: Dictionary = {}
var _sites: Array[EcsSettlementSite] = []

func _ready() -> void:
	CATALOG.number()
	_every_town_gets_sound_plots()
	_buildings_stand_where_their_rules_say()
	_the_same_seed_gives_the_same_plots()
	_plots_load_through_the_build_system()
	print("[plot] %d/%d checks passed" % [_checks - _failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)

func _region() -> EcsLandDef:
	return load(REGION) as EcsLandDef

func _plan(region: EcsLandDef, rng_seed: int) -> Dictionary:
	if not _plans.has(rng_seed):
		var plan := EcsTerrainGenerator.plan(region, rng_seed, CATALOG, ENTITIES)
		_plans[rng_seed] = {"plan": plan, "shares": EcsTerrainGenerator.blend_shares(plan, region)}
	return _plans[rng_seed]

func _pick(region: EcsLandDef, rng_seed: int, town: StringName) -> EcsSettlementSite:
	var p := _plan(region, rng_seed)
	return EcsSitePicker.pick(p["plan"], region, load(DEFS % town), rng_seed, ZOOM, CATALOG, p["shares"])

## Every town size over several seeds: every building on its list has a plot or is reported short,
## plots sound and standing where their rules say, every door on a road, and roads, lanes and
## tracks one network joined to the plaza. Works out of the area stand in outlying windows.
func _every_town_gets_sound_plots() -> void:
	var region := _region()
	for town in TOWNS:
		var def := load(DEFS % town) as EcsSettlementDef
		var first: Array[String] = []
		var usec := 0
		var plots := 0
		var wanted := 0
		var short := 0
		var outlying := 0
		var windows := 0
		var grown := 0
		var short_by: Dictionary = {}
		for s in SEEDS:
			var started := Time.get_ticks_usec()
			var site := _pick(region, s, town)
			usec += Time.get_ticks_usec() - started
			_sites.append(site)
			var p := _plan(region, s)
			var problems := EcsPlotCheck.problems(site, p["plan"], region, def, s, ZOOM, p["shares"])
			problems.append_array(EcsRoadCheck.problems(site, p["plan"], region, def, s, ZOOM, p["shares"]))
			var listed := 0
			for entry: Dictionary in site.economy["roles"]:
				listed += int(entry["count"])
			var missing := 0
			for entry: Dictionary in site.economy["short"]:
				missing += int(entry["count"])
				short_by[entry["role"]] = int(short_by.get(entry["role"], 0)) + int(entry["count"])
			if site.plots.size() + missing != listed:
				problems.append("%d plots and %d short for %d buildings" % [site.plots.size(), missing, listed])
			for plot in site.plots:
				if not site.area.encloses(plot["footprint"]):
					outlying += 1
					if EcsTownEconomy.CATALOG.role(plot["role"]).group != &"works" and EcsPlotPlanner._resource_of(EcsTownEconomy.CATALOG.role(plot["role"]), site.survey) == &"":
						problems.append("a %s outside the area" % plot["role"])
			plots += site.plots.size()
			wanted += listed
			short += missing
			windows += site.outlying.size()
			grown += 1 if site.area.size != def.size else 0
			if not problems.is_empty() and first.is_empty():
				first = problems
				first.push_front("seed %d:" % s)
		_check("%s: %d seeds, %d of %d buildings placed (%d short), %d in %d outlying windows, %d areas grown, all sound%s" % [town, SEEDS,
			plots, wanted, short, outlying, windows, grown, "" if first.is_empty() else "  " + " ".join(first)],
			first.is_empty() and plots >= wanted * 0.9)
		print("[plot]   %s: a town with its roads and plots takes %d ms on average; short: %s" % [town, usec / SEEDS / 1000, short_by])

## Where buildings land: the manor faces the plaza, every farmhouse its field and every herder, barn
## and stable its pen, and houses stand
## nearer the plaza than farmhouses.
func _buildings_stand_where_their_rules_say() -> void:
	var manors := 0
	var on_plaza := 0
	var houses := [0.0, 0]
	var farms := [0.0, 0]
	for site in _sites:
		for plot in site.plots:
			var d := Vector2((plot["footprint"] as Rect2i).get_center()).distance_to(Vector2(site.well))
			match plot["role"]:
				&"manor":
					manors += 1
					on_plaza += 1 if site.plaza.grow(1).has_point(plot["door"] + plot["front"]) else 0
				&"house":
					houses[0] += d
					houses[1] += 1
				&"farmhouse":
					farms[0] += d
					farms[1] += 1
	var annexes := 0
	var wanted := 0
	for site in _sites:
		for plot in site.plots:
			var annex := EcsTownEconomy.CATALOG.role(plot["role"]).annex
			if annex == &"field" or annex == &"pen":
				wanted += 1
				annexes += 1 if plot.get("annex_kind", &"") == annex else 0
	_check("%d of %d farmhouses, herders, barns and stables have their field or pen beside them" % [annexes, wanted], wanted > 0 and annexes == wanted)
	var house_d: float = houses[0] / maxi(houses[1], 1)
	var farm_d: float = farms[0] / maxi(farms[1], 1)
	_check("%d of %d manors face the plaza" % [on_plaza, manors], manors > 0 and on_plaza == manors)
	_check("houses stand %.0f cells from the well on average, farmhouses %.0f" % [house_d, farm_d], farms[1] > 0 and house_d < farm_d)

func _the_same_seed_gives_the_same_plots() -> void:
	var a := _pick(_region(), 1, &"village")
	var b := _pick(_region(), 1, &"village")
	var same := a.plots.size() == b.plots.size() and a.road_cells.size() == b.road_cells.size()
	for k in mini(a.plots.size(), b.plots.size()):
		same = same and a.plots[k]["footprint"] == b.plots[k]["footprint"] and a.plots[k]["door"] == b.plots[k]["door"] and a.plots[k]["role"] == b.plots[k]["role"]
	_check("the same seed gives the same plots and lanes (%d plots)" % a.plots.size(), same)

## A hamlet's area with plaza, roads, plots and nodes through module 10's build system: every command
## accepted, the road floor on every lane, and no node on a footprint or yard.
func _plots_load_through_the_build_system() -> void:
	var region := _region()
	var p := _plan(region, 2)
	var def := load(DEFS % &"hamlet") as EcsSettlementDef
	var site := _pick(region, 2, &"hamlet")
	var area := site.area
	var terrain := EcsTerrainGenerator.refine_terrain(p["plan"], region, area.size, region.child.shore_width, area.position, ZOOM, 2, 0, p["shares"])
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
	var nodes := EcsTerrainGenerator.refine_nodes(_land(region, area.size), terrain["zones"], 2, area.position, ENTITIES, blocked)
	var commands := EcsTerrainGenerator.terrain_commands(terrain["kinds"], area.size, Vector2i.ZERO, CATALOG)
	var on_plot := 0
	for node: Dictionary in nodes:
		commands.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, node["cell"], node["blueprint"], 0))
		var rect := Rect2i(area.position + (node["cell"] as Vector2i), node["size"])
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				on_plot += 1 if site.plot_at.has(Vector2i(x, y)) else 0
	# The town's commands on the area's cells; main roads and outlying works run on past it.
	commands.append_array(EcsTerrainChunks.clip(site, area, 0, true))
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
	var refused := commands.filter(func(c: EcsBuildCommand) -> bool: return c.result != &"ok")
	var first := "" if refused.is_empty() else "  first: %s at %s %s" % [EcsBuildCommand.Kind.keys()[refused[0].kind], refused[0].cell + area.position, refused[0].result]
	_check("all %d commands of the hamlet's area accepted by the build system (%d refused)%s" % [commands.size(), refused.size(), first], refused.is_empty())
	var road := CATALOG.floor_id(def.road_floor)
	var lanes := 0
	var floored := true
	for cell: Vector2i in site.road_cells:
		if site.road_cells[cell] == &"lane" and area.has_point(cell):
			lanes += 1
			floored = floored and grid.floor[EcsTownGrid.index(grid, cell - area.position)] == road
	_check("every one of %d lane cells has the road floor" % lanes, floored and lanes > 0)
	_check("no node on a footprint or yard (%d plots, %d nodes planned)" % [site.plots.size(), nodes.size()], on_plot == 0)
	root.free()

## The region's L1 land, `size` cells: what a town's area or a chunk grows.
func _land(region: EcsLandDef, size: Vector2i) -> EcsLandDef:
	var land := region.child.duplicate() as EcsLandDef
	land.size = size
	return land

func _check(what: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
	print("[plot] %s  %s" % ["ok  " if passed else "FAIL", what])
