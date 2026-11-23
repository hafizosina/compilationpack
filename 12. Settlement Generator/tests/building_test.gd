extends Node2D

## Headless test for module 12's step 6: a building on every walled plot.
##
##   "$GODOT" --headless --path . "res://12. Settlement Generator/tests/building_test.tscn"
##
## Exits 0 only if every check passes. Prints how long building a town takes.

const CATALOG := preload("res://10. Town Generator/defs/town_catalog.tres")
const ENTITIES := preload("res://10. Town Generator/defs/entity_catalog.tres")
const DEFS := "res://12. Settlement Generator/defs/settlements/%s.tres"
const REGION := "res://12. Settlement Generator/defs/lands/region.tres"
const TOWNS: Array[StringName] = [&"hamlet", &"village", &"town"]
const SEEDS: int = 3
const ZOOM: int = 8
const CHUNK: int = 32

var _checks: int = 0
var _failures: int = 0
var _plans: Dictionary = {}

func _ready() -> void:
	CATALOG.number()
	_every_walled_plot_gets_a_sound_building()
	_a_building_across_chunks_draws_as_one()
	print("[building] %d/%d checks passed" % [_checks - _failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)

func _region() -> EcsLandDef:
	return load(REGION) as EcsLandDef

func _plan(region: EcsLandDef, rng_seed: int) -> Dictionary:
	if not _plans.has(rng_seed):
		var plan := EcsTerrainGenerator.plan(region, rng_seed, CATALOG, ENTITIES)
		_plans[rng_seed] = {"plan": plan, "shares": EcsTerrainGenerator.blend_shares(plan, region)}
	return _plans[rng_seed]

func _pick(rng_seed: int, town: StringName) -> EcsSettlementSite:
	var p := _plan(_region(), rng_seed)
	return EcsSitePicker.pick(p["plan"], _region(), load(DEFS % town), rng_seed, ZOOM, CATALOG, p["shares"])

## Every town size over seeds: every walled plot has a building, every one accepted by module
## 10's build system in a world of the town's area or its window, sound by EcsBuildingCheck, and
## entered from a road.
func _every_walled_plot_gets_a_sound_building() -> void:
	for town in TOWNS:
		var first := ""
		var built := 0
		var shapes: Dictionary = {}
		var usec := 0
		for s in SEEDS:
			var started := Time.get_ticks_usec()
			var site := _pick(s, town)
			usec += Time.get_ticks_usec() - started
			if not (site.economy["unbuilt"] as Array).is_empty():
				first = "seed %d: no building type for %s" % [s, site.economy["unbuilt"]]
			var grounds: Array[Rect2i] = [site.area]
			for window: Dictionary in site.outlying:
				grounds.append(window["rect"])
			for ground in grounds:
				var world := _world(ground.size, EcsTerrainChunks.clip(site, ground, 0, true))
				var grid := world["grid"] as EcsTownGridSingleton
				for command: EcsBuildCommand in world["commands"]:
					if command.result != &"ok" and first == "":
						first = "seed %d: %s at %s %s" % [s, EcsBuildCommand.Kind.keys()[command.kind], command.cell + ground.position, command.result]
				for k in site.plots.size():
					var plot := site.plots[k]
					var role := EcsTownCensus.CATALOG.role(plot["role"])
					if not ground.encloses(plot["footprint"]) or role.building == &"":
						continue
					if not plot.has("building"):
						if first == "":
							first = "seed %d: plot %d, a %s, has no building" % [s, k, role.key]
						continue
					built += 1
					var b: Dictionary = plot["building"]
					shapes[b["shape"]] = int(shapes.get(b["shape"], 0)) + 1
					var entrance: Vector2i = b["entrance"]
					var local: Vector2i = (b.get("at", (plot["footprint"] as Rect2i).position) as Vector2i) - ground.position
					var id := grid.building_id[EcsTownGrid.index(grid, local)]
					for problem in EcsBuildingCheck.problems(world["world"], grid, id, entrance - ground.position):
						if first == "":
							first = "seed %d: plot %d, a %s: %s" % [s, k, role.key, problem]
					# A compound is entered by its gate; its house stands behind it.
					var way_in: Vector2i = b.get("gate", entrance)
					if not site.road_cells.has(way_in + plot["front"]) and not site.plaza.has_point(way_in + plot["front"]) and first == "":
						first = "seed %d: plot %d, a %s, entered from no road" % [s, k, role.key]
				(world["root"] as Node).free()
		_check("%s: %d seeds, %d buildings, all accepted, sound and entered from a road; shapes %s%s" % [town, SEEDS, built, shapes,
			"" if first == "" else "  " + first], first == "" and built > 0)
		print("[building]   %s: a town with its buildings takes %d ms on average" % [town, usec / SEEDS / 1000])

## A building crossing chunk lines: each chunk's clipped commands are accepted, and its walls,
## floors and roof on the chunk's own cells are the whole building's.
func _a_building_across_chunks_draws_as_one() -> void:
	var site := _pick(0, &"village")
	# The building crossing the most chunks: both lines if one does.
	var target := -1
	var most := 1
	for k in site.plots.size():
		var rect: Rect2i = site.plots[k]["footprint"]
		if not site.plots[k].has("building") or not site.area.encloses(rect):
			continue
		var crossed := (floori((rect.end.x - 1) / float(CHUNK)) - floori(rect.position.x / float(CHUNK)) + 1) \
			* (floori((rect.end.y - 1) / float(CHUNK)) - floori(rect.position.y / float(CHUNK)) + 1)
		if crossed > most:
			most = crossed
			target = k
	if target < 0:
		_check("a building crossing a chunk line", false)
		return
	var rect: Rect2i = site.plots[target]["footprint"]
	var whole := _world(site.area.size, EcsTerrainChunks.clip(site, site.area, 0, true))
	var whole_grid := whole["grid"] as EcsTownGridSingleton
	var chunks := EcsTerrainChunks.new(_region().size, ZOOM, CHUNK)
	chunks.site = site
	var under := chunks.touching(rect.grow(-1))
	var refused := 0
	var first_refused := ""
	var differ := 0
	var roofed := 0
	for at in under:
		var part := _world(Vector2i(CHUNK + 2, CHUNK + 2), chunks.overlay(at, true))
		var grid := part["grid"] as EcsTownGridSingleton
		for c: EcsBuildCommand in part["commands"]:
			if c.result != &"ok":
				refused += 1
				if first_refused == "":
					first_refused = "  first: %s %s at %s %s" % [EcsBuildCommand.Kind.keys()[c.kind], c.blueprint, c.cell, c.result]
		var own := Rect2i(at * CHUNK, Vector2i(CHUNK, CHUNK)).intersection(rect)
		for cell in EcsBuildRules.cells(own):
			var i := EcsTownGrid.index(grid, cell - at * CHUNK + Vector2i.ONE)
			var w := EcsTownGrid.index(whole_grid, cell - site.area.position)
			roofed += 1 if whole_grid.roof[w] != 0 else 0
			if grid.structure[i] != whole_grid.structure[w] or grid.floor[i] != whole_grid.floor[w] or grid.roof[i] != whole_grid.roof[w]:
				differ += 1
		(part["root"] as Node).free()
	(whole["root"] as Node).free()
	_check("a %s %s across %d chunks: every clipped command accepted (%d refused), %d cells differ from the whole building (%d roofed)%s" % [
		site.plots[target]["role"], rect, under.size(), refused, differ, roofed, first_refused], under.size() >= 2 and refused == 0 and differ == 0 and roofed > 0)

## A world of `size` with `commands` sent through lifecycle, build, room detection and roofs.
func _world(size: Vector2i, commands: Array[EcsBuildCommand]) -> Dictionary:
	var world := EcsWorld.new()
	var grid := EcsTownGrid.make(size.x, size.y, CATALOG.terrain_id(&"grass"))
	grid.commands.append_array(commands)
	world.add_singleton(grid)
	world.add_singleton(EcsLifecycleSingleton.new())
	var root := Node2D.new()
	add_child(root)
	var scheduler := EcsScheduler.new()
	scheduler.add(EcsLifecycleSystem.new(EcsEntityManager.new(root), ENTITIES)).add(EcsBuildCommandSystem.new(CATALOG, ENTITIES)) \
		.add(EcsRoomDetectionSystem.new(CATALOG)).add(EcsRoofSystem.new(CATALOG))
	for tick in 4:
		scheduler.run_all(world, 1.0 / 60.0)
	return {"world": world, "grid": grid, "root": root, "commands": commands}

func _check(what: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
	print("[building] %s  %s" % ["ok  " if passed else "FAIL", what])
