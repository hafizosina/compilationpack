extends Node2D

## Headless test for module 12's step 7a: outdoor works, fenced fields and pens, docks, wheels.
##
##   "$GODOT" --headless --path . "res://12. Settlement Generator/tests/outdoor_test.tscn"
##
## Exits 0 only if every check passes.

const CATALOG := preload("res://10. Town Generator/defs/town_catalog.tres")
const ENTITIES := preload("res://10. Town Generator/defs/entity_catalog.tres")
const DEFS := "res://12. Settlement Generator/defs/settlements/%s.tres"
const REGION := "res://12. Settlement Generator/defs/lands/region.tres"
const TOWNS: Array[StringName] = [&"hamlet", &"village", &"town"]
const SEEDS: int = 3
const ZOOM: int = 8
const WORKS: Array[StringName] = [&"market", &"mine", &"quarry", &"lumber_camp", &"clay_pit", &"harbour", &"shrine"]

var _checks: int = 0
var _failures: int = 0
var _plans: Dictionary = {}
var _sites: Array[EcsSettlementSite] = []

func _ready() -> void:
	CATALOG.number()
	for town in TOWNS:
		for s in SEEDS:
			_sites.append(_pick(s, town))
	_every_outdoor_work_is_laid()
	_every_rule_lays_its_work()
	_fields_and_pens_are_fenced_with_a_gate()
	_docks_and_wheels_stand_on_water()
	_every_entrance_can_be_walked_to()
	print("[outdoor] %d/%d checks passed" % [_checks - _failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)

func _region() -> EcsLandDef:
	return load(REGION) as EcsLandDef

func _plan(rng_seed: int) -> Dictionary:
	if not _plans.has(rng_seed):
		var plan := EcsTerrainGenerator.plan(_region(), rng_seed, CATALOG, ENTITIES)
		_plans[rng_seed] = {"plan": plan, "shares": EcsTerrainGenerator.blend_shares(plan, _region()), "seed": rng_seed}
	return _plans[rng_seed]

func _pick(rng_seed: int, town: StringName) -> EcsSettlementSite:
	var p := _plan(rng_seed)
	var site := EcsSitePicker.pick(p["plan"], _region(), load(DEFS % town), rng_seed, ZOOM, CATALOG, p["shares"])
	site.set_meta(&"seed", rng_seed)
	return site

## The objects `site` places inside `rect`, by blueprint.
func _objects_in(site: EcsSettlementSite, rect: Rect2i) -> Dictionary:
	var out: Dictionary = {}
	for command in site.commands:
		if command.kind == EcsBuildCommand.Kind.PLACE_OBJECT and rect.has_point(command.cell):
			out[command.blueprint] = int(out.get(command.blueprint, 0)) + 1
	return out

## Every plot of an outdoor work holds pieces, its way in clear, and no work is left without a rule.
func _every_outdoor_work_is_laid() -> void:
	var laid: Dictionary = {}
	var bare := ""
	for site in _sites:
		if not (site.economy["unbuilt"] as Array).is_empty() and bare == "":
			bare = "no rule or type for %s" % [site.economy["unbuilt"]]
		for plot in site.plots:
			if not WORKS.has(plot["role"]):
				continue
			var pieces := _objects_in(site, plot["footprint"])
			if pieces.is_empty() and bare == "":
				bare = "a %s at %s with nothing on it" % [plot["role"], plot["footprint"]]
			for command in site.commands:
				if command.kind == EcsBuildCommand.Kind.PLACE_OBJECT and (command.cell == plot["door"] or command.cell == plot["door"] - plot["front"]) and bare == "":
					bare = "a %s's way in blocked by a %s" % [plot["role"], command.blueprint]
			laid[plot["role"]] = int(laid.get(plot["role"], 0)) + 1
	_check("outdoor works laid: %s%s" % [laid, "" if bare == "" else "  " + bare], bare == "" and laid.size() >= 3)

## Each work's rule, on a plot of its own size facing each way: it places pieces, all inside the
## footprint, none on the way in. Covers the works the towns above may not have.
func _every_rule_lays_its_work() -> void:
	var first := ""
	var pieces := 0
	for key in WORKS:
		var role := EcsTownEconomy.CATALOG.role(key)
		for front in EcsPlotPlanner.SIDES:
			var site := EcsSettlementSite.new()
			var rect := Rect2i(Vector2i(20, 20), role.size_max)
			var door := EcsPlotPlanner._door(rect, front)
			var plot := {"role": key, "footprint": rect, "front": front, "door": door, "yard": []}
			if not EcsOutdoorBuilder.lay(site, plot, load(DEFS % &"town"), CATALOG, 7):
				first = "%s has no rule" % key
				continue
			var placed := 0
			for command in site.commands:
				if command.kind != EcsBuildCommand.Kind.PLACE_OBJECT:
					continue
				placed += 1
				if not rect.has_point(command.cell) and first == "":
					first = "a %s's %s outside it" % [key, command.blueprint]
				if (command.cell == door or command.cell == door - front) and first == "":
					first = "a %s's way in blocked by a %s" % [key, command.blueprint]
			pieces += placed
			if placed == 0 and first == "":
				first = "a %s facing %s has nothing on it" % [key, front]
	_check("every work's rule, facing every way, lays %d pieces, none outside or on the way in%s" % [pieces, "" if first == "" else "  " + first], first == "")

## Every field and pen has a fence on every edge cell but a 2-cell gate, the gate facing its house.
func _fields_and_pens_are_fenced_with_a_gate() -> void:
	var fenced := 0
	var all := 0
	var first := ""
	for site in _sites:
		var fence_at: Dictionary = {}
		for command in site.commands:
			if command.kind == EcsBuildCommand.Kind.PLACE_OBJECT and command.blueprint == &"fence":
				fence_at[command.cell] = true
		for plot in site.plots:
			if not plot.has("annex"):
				continue
			all += 1
			var annex: Rect2i = plot["annex"]
			var edge := 0
			var gaps: Array[Vector2i] = []
			for cell in EcsBuildRules.cells(annex):
				if annex.grow(-1).has_point(cell):
					continue
				edge += 1
				if not fence_at.has(cell):
					gaps.append(cell)
			var house: Rect2i = plot["footprint"]
			var facing := gaps.size() == 2 and gaps.all(func(c: Vector2i) -> bool: return house.grow(3).has_point(c))
			if facing:
				fenced += 1
			elif first == "":
				first = "a %s's %s at %s: %d gaps of %d edge cells" % [plot["role"], plot["annex_kind"], annex, gaps.size(), edge]
	_check("%d of %d fields and pens fenced with a 2-cell gate facing the house%s" % [fenced, all, "" if first == "" else "  " + first],
		all > 0 and fenced == all)

## Every dock lies on water, wood-floored and walkable through module 10's nav (but for its mooring
## post's cell); every watermill's
## wheel stands on river water.
func _docks_and_wheels_stand_on_water() -> void:
	var docks := 0
	var wanted := 0
	var walkable := 0
	var cells := 0
	var wheels := 0
	var mills := 0
	for site in _sites:
		for plot in site.plots:
			var role := EcsTownEconomy.CATALOG.role(plot["role"])
			mills += 1 if role.key == &"watermill" else 0
			wheels += 1 if plot.has("wheel") else 0
			if role.annex != &"dock":
				continue
			wanted += 1
			if not plot.has("dock"):
				continue
			docks += 1
			var ground := _ground_of(site, plot["footprint"])
			var world := _world(site, ground, true)
			var nav := (world["world"] as EcsWorld).get_singleton(EcsTownNavSingleton) as EcsTownNavSingleton
			var grid := world["grid"] as EcsTownGridSingleton
			for cell: Vector2i in plot["dock"]["cells"]:
				# The mooring post stands on the pier's end and blocks its own cell.
				if cell == plot["dock"]["post"]:
					continue
				cells += 1
				var local := cell - ground.position
				if grid.terrain[EcsTownGrid.index(grid, local)] == CATALOG.terrain_id(&"water") and EcsTownNavSystem.walkable(nav, local):
					walkable += 1
			(world["root"] as Node).free()
	_check("%d of %d docks laid; %d of %d dock cells water under wood and walkable" % [docks, wanted, walkable, cells],
		docks > 0 and walkable == cells)
	_check("%d of %d watermills have their wheel on the river" % [wheels, mills], wheels == mills)

## The town's area or outlying window that holds `rect`.
func _ground_of(site: EcsSettlementSite, rect: Rect2i) -> Rect2i:
	for window: Dictionary in site.outlying:
		if (window["rect"] as Rect2i).encloses(rect):
			return window["rect"]
	return site.area

## In each town's area, with its terrain, buildings, fences and docks through module 10: every
## command accepted, and every building's entrance reachable on foot from the well.
func _every_entrance_can_be_walked_to() -> void:
	var refused := 0
	var reached := 0
	var entrances := 0
	var first := ""
	for site in _sites:
		var world := _world(site, site.area, true)
		var grid := world["grid"] as EcsTownGridSingleton
		var nav := (world["world"] as EcsWorld).get_singleton(EcsTownNavSingleton) as EcsTownNavSingleton
		for command: EcsBuildCommand in world["commands"]:
			if command.result != &"ok":
				refused += 1
				if first == "":
					first = "%s %s at %s %s" % [command.blueprint, EcsBuildCommand.Kind.keys()[command.kind], command.cell + site.area.position, command.result]
		var start := site.well - site.area.position + Vector2i.RIGHT
		var seen: Dictionary = {start: true}
		var queue: Array[Vector2i] = [start]
		while not queue.is_empty():
			var at: Vector2i = queue.pop_back()
			for side in EcsPlotPlanner.SIDES:
				var next := at + side
				if seen.has(next) or not Rect2i(Vector2i.ZERO, site.area.size).has_point(next) or not EcsTownNavSystem.walkable(nav, next):
					continue
				seen[next] = true
				queue.append(next)
		for plot in site.plots:
			if not plot.has("building") or not site.area.encloses(plot["footprint"]):
				continue
			entrances += 1
			if seen.has((plot["building"]["entrance"] as Vector2i) - site.area.position):
				reached += 1
		(world["root"] as Node).free()
	_check("every command of %d towns' areas accepted (%d refused)%s" % [_sites.size(), refused, "" if first == "" else "  first: " + first], refused == 0)
	_check("%d of %d entrances walkable from the well, past every fence" % [reached, entrances], entrances > 0 and reached == entrances)

## A world of `ground` with its refined terrain and the town's commands on it, through lifecycle,
## build and nav.
func _world(site: EcsSettlementSite, ground: Rect2i, with_terrain: bool) -> Dictionary:
	var p: Dictionary = _plans[site.get_meta(&"seed")]
	var commands: Array[EcsBuildCommand] = []
	if with_terrain:
		var terrain := EcsTerrainGenerator.refine_terrain(p["plan"], _region(), ground.size, _region().child.shore_width,
			ground.position, ZOOM, p["seed"], 0, p["shares"])
		commands.append_array(EcsTerrainGenerator.terrain_commands(terrain["kinds"], ground.size, Vector2i.ZERO, CATALOG))
	commands.append_array(EcsTerrainChunks.clip(site, ground, 0, true))
	var world := EcsWorld.new()
	var grid := EcsTownGrid.make(ground.size.x, ground.size.y, CATALOG.terrain_id(&"grass"))
	grid.commands.append_array(commands)
	world.add_singleton(grid)
	world.add_singleton(EcsLifecycleSingleton.new())
	world.add_singleton(EcsTownNavSingleton.new())
	var root := Node2D.new()
	add_child(root)
	var scheduler := EcsScheduler.new()
	scheduler.add(EcsLifecycleSystem.new(EcsEntityManager.new(root), ENTITIES)).add(EcsBuildCommandSystem.new(CATALOG, ENTITIES)) \
		.add(EcsTownNavSystem.new(CATALOG))
	for tick in 4:
		scheduler.run_all(world, 1.0 / 60.0)
	return {"world": world, "grid": grid, "root": root, "commands": commands}

func _check(what: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
	print("[outdoor] %s  %s" % ["ok  " if passed else "FAIL", what])
