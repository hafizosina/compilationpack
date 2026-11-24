extends Node2D

## Headless test for module 13's terrain: module 12's checks on the copied generator (maps on their
## own, an L2 region, L1 windows zoomed into it), then the L3 world, L2 regions refined from its
## windows and L1 windows refined from those.
##
##   "$GODOT" --headless --path . "res://13. World Generator/tests/terrain_test.tscn"
##
## Exits 0 only if every check passes. Prints plan and load costs per size.

const CATALOG := preload("res://10. Town Generator/defs/town_catalog.tres")
const ENTITIES := preload("res://10. Town Generator/defs/entity_catalog.tres")
const DEFS := "res://13. World Generator/defs/settlements/%s.tres"
const REGION := "res://13. World Generator/defs/lands/region.tres"
const L1 := "res://13. World Generator/defs/lands/l1.tres"
const WORLD := "res://13. World Generator/defs/lands/world.tres"
## Maps planned on their own, by size: [size, usual water, its share].
const MAPS := {
	&"hamlet": [Vector2i(160, 120), WorldLandDef.Water.LAKE, 0.12],
	&"village": [Vector2i(256, 192), WorldLandDef.Water.RIVER, 0.03],
	&"town": [Vector2i(384, 288), WorldLandDef.Water.COAST, 0.15],
}
const SIZES: Array[StringName] = [&"hamlet", &"village", &"town"]
## Seeds checked per water kind, by size: fewer on the big maps, which take longer.
const SEEDS: Array[int] = [20, 10, 5]
const WATER_NAMES: Array[String] = ["lake", "river", "coast", "river to the sea"]
## L1 cells per L2 cell side.
const ZOOM: int = 8

var _checks: int = 0
var _failures: int = 0

func _ready() -> void:
	CATALOG.number()
	_every_size_and_water_is_sound()
	_the_same_seed_gives_the_same_map()
	for key in SIZES:
		var def := _def(key, -1)
		_a_map_loads_through_the_build_system(key, def, WorldTerrainGenerator.plan(def, 1, CATALOG, ENTITIES))
	_a_region_is_sound()
	_a_zoomed_window_follows_its_region()
	_veins_grow_only_in_their_deposits()
	_neighbouring_windows_meet_without_a_seam()
	_chunk_borders_are_their_neighbours_cells()
	_chunks_are_made_in_order_and_kept()
	_the_world_is_sound()
	_regions_follow_the_world_and_l1_follows_them()
	_neighbouring_regions_meet_without_a_seam()
	_regions_are_made_in_order_and_kept()
	print("[terrain] %d/%d checks passed" % [_checks - _failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)

## L1 land planned on its own at `key`'s size, with its usual water or `water` (-1 keeps it); a
## river's share is its width's, so it gets one to match.
func _def(key: StringName, water: int) -> WorldLandDef:
	var def := (load(L1) as WorldLandDef).duplicate() as WorldLandDef
	var usual: Array = MAPS[key]
	def.size = usual[0]
	def.water = usual[1]
	def.water_share = usual[2]
	if water >= 0 and water != def.water:
		def.water = water
		def.water_share = 0.03 if water == WorldLandDef.Water.RIVER else 0.12
	return def

## Every size with every kind of water, over several seeds, passes WorldTerrainCheck.
func _every_size_and_water_is_sound() -> void:
	for k in SIZES.size():
		for water in 3:
			var def := _def(SIZES[k], water)
			var first: Array[String] = []
			var sound := 0
			var usec := 0
			for s in SEEDS[k]:
				var plan := WorldTerrainGenerator.plan(def, s, CATALOG, ENTITIES)
				usec += _sum(plan["usec"])
				var problems := WorldTerrainCheck.problems(def, plan)
				if problems.is_empty():
					sound += 1
				elif first.is_empty():
					first = problems
					first.push_front("seed %d:" % s)
			_check("%s %s: %d seeds, every map sound%s" % [SIZES[k], WATER_NAMES[water], SEEDS[k],
				"" if first.is_empty() else "  " + " ".join(first)], sound == SEEDS[k])
			print("[terrain]   %s %s %dx%d: plan %d ms on average" % [SIZES[k], WATER_NAMES[water], def.size.x, def.size.y,
				usec / SEEDS[k] / 1000])

## A seed gives the same commands every time; the next seed gives other ones.
func _the_same_seed_gives_the_same_map() -> void:
	var def := _def(&"hamlet", WorldLandDef.Water.LAKE)
	var a := _fingerprint(WorldTerrainGenerator.plan(def, 7, CATALOG, ENTITIES))
	var b := _fingerprint(WorldTerrainGenerator.plan(def, 7, CATALOG, ENTITIES))
	var c := _fingerprint(WorldTerrainGenerator.plan(def, 8, CATALOG, ENTITIES))
	_check("the same seed gives the same commands", a == b)
	_check("the next seed gives other ones", a != c)

## The L2 region, a river into the sea, over several seeds passes WorldTerrainCheck.
func _a_region_is_sound() -> void:
	var region := load(REGION) as WorldLandDef
	var bad: Array[String] = []
	for s in 10:
		var problems := WorldTerrainCheck.problems(region, WorldTerrainGenerator.plan(region, s, CATALOG, ENTITIES))
		if not problems.is_empty() and bad.is_empty():
			bad = problems
			bad.push_front("seed %d:" % s)
	_check("the L2 region (%dx%d, river to the sea): 10 seeds, every map sound%s" % [region.size.x, region.size.y,
		"" if bad.is_empty() else "  " + " ".join(bad)], bad.is_empty())

## L1 windows 8x into a region — on the river, on the coast, inland — follow it: every L2 cell
## whose neighbourhood is one kind is all that kind below, nearly every block's most common kind
## is its parent's, and each window is sound. One loads through the build system.
func _a_zoomed_window_follows_its_region() -> void:
	var region := load(REGION) as WorldLandDef
	var town := _land(region, MAPS[&"town"][0])
	var window := town.size / ZOOM
	for s in 3:
		var parent := WorldTerrainGenerator.plan(region, s, CATALOG, ENTITIES)
		var points := ((parent["rivers"] as Array)[0] as Dictionary)["points"] as PackedVector2Array
		var on_river := Vector2i(points[points.size() / 2]) - window / 2
		var side := parent["coast_side"] as Vector2i
		var on_coast := (region.size - window) / 2 + Vector2i(side.x * region.size.x / 2, side.y * region.size.y / 2)
		var places := {"on the river": on_river, "on the coast": on_coast, "inland": Vector2i(8, 8) if side != Vector2i.LEFT and side != Vector2i.UP else region.size - window - Vector2i(8, 8)}
		for name: String in places:
			var origin: Vector2i = (places[name] as Vector2i).clamp(Vector2i.ZERO, region.size - window)
			var started := Time.get_ticks_usec()
			var child := WorldTerrainGenerator.refine(parent, region, town, origin, ZOOM, s, CATALOG, ENTITIES)
			var spent := Time.get_ticks_usec() - started
			var problems := WorldTerrainCheck.follows(parent, region, child, town, origin, ZOOM)
			problems.append_array(WorldTerrainCheck.problems(town, child, true))
			_check("seed %d, an L1 window %s at %s follows its region and is sound (%d ms)%s" % [s, name, origin,
				spent / 1000, "" if problems.is_empty() else "  " + " ".join(problems)], problems.is_empty())
			if s == 0 and name == "on the river":
				_a_map_loads_through_the_build_system(&"L1 window", town, child)

## The region's deposits lie on their ground, and L1 veins and clay pits grow only inside a deposit
## of their kind: plenty round each iron deposit, none on rock outside every deposit.
func _veins_grow_only_in_their_deposits() -> void:
	var region := load(REGION) as WorldLandDef
	const AREA := 64
	var town := _land(region, Vector2i(AREA, AREA))
	var by_node := {}
	for spawn in town.nodes:
		if spawn.deposit != &"":
			by_node[spawn.blueprint] = spawn.deposit
	for s in 3:
		var parent := WorldTerrainGenerator.plan(region, s, CATALOG, ENTITIES)
		var deposits := parent["deposits"] as Dictionary
		var ids := deposits["ids"] as PackedByteArray
		var kinds := parent["kinds"] as PackedByteArray
		var grounds := {}
		for d in region.deposits:
			grounds[d.key] = d.ground
		var on_ground := true
		var cells := {}
		for i in ids.size():
			if ids[i] != 0:
				var key: StringName = deposits["keys"][ids[i] - 1]
				on_ground = on_ground and kinds[i] == grounds[key]
				cells[key] = int(cells.get(key, 0)) + 1
		var shares := WorldTerrainGenerator.blend_shares(parent, region)
		var veins := 0
		var stray := 0
		for blob: Dictionary in deposits["blobs"]:
			if blob["key"] != &"iron":
				continue
			var at := (blob["cell"] as Vector2i) * ZOOM + Vector2i(ZOOM, ZOOM) / 2 - Vector2i(AREA, AREA) / 2
			var terrain := WorldTerrainGenerator.refine_terrain(parent, region, Vector2i(AREA, AREA), town.shore_width, at, ZOOM, s, 0, shares)
			var nodes := WorldTerrainGenerator.refine_nodes(town, terrain["zones"], s, at, ENTITIES, PackedByteArray(), terrain["deposits"])
			for node: Dictionary in nodes:
				if not by_node.has(node["blueprint"]):
					continue
				var cell: Vector2i = (at + (node["cell"] as Vector2i)) / ZOOM
				var id := ids[cell.y * region.size.x + cell.x]
				if id == 0 or deposits["keys"][id - 1] != by_node[node["blueprint"]]:
					stray += 1
				elif node["blueprint"] == &"iron_vein":
					veins += 1
		_check("seed %d: deposits on their ground (%s), %d iron veins round its iron deposits, %d veins outside a deposit of their kind" % [s,
			", ".join(cells.keys().map(func(k: StringName) -> String: return "%s %d cells" % [k, cells[k]])), veins, stray],
			on_ground and cells.has(&"iron") and veins > 0 and stray == 0)

## Two windows side by side are cell for cell the halves of one window twice as wide.
func _neighbouring_windows_meet_without_a_seam() -> void:
	var region := load(REGION) as WorldLandDef
	var town := _land(region, MAPS[&"town"][0])
	var parent := WorldTerrainGenerator.plan(region, 4, CATALOG, ENTITIES)
	var points := ((parent["rivers"] as Array)[0] as Dictionary)["points"] as PackedVector2Array
	var window := town.size / ZOOM
	var origin := (Vector2i(points[points.size() / 2]) - window).clamp(Vector2i.ZERO, region.size - window * Vector2i(2, 1))
	var wide := town.duplicate() as WorldLandDef
	wide.size = Vector2i(town.size.x * 2, town.size.y)
	var left := WorldTerrainGenerator.refine(parent, region, town, origin, ZOOM, 4, CATALOG, ENTITIES)["kinds"] as PackedByteArray
	var right := WorldTerrainGenerator.refine(parent, region, town, origin + Vector2i(window.x, 0), ZOOM, 4, CATALOG, ENTITIES)["kinds"] as PackedByteArray
	var both := WorldTerrainGenerator.refine(parent, region, wide, origin, ZOOM, 4, CATALOG, ENTITIES)["kinds"] as PackedByteArray
	var same := true
	for y in town.size.y:
		for x in town.size.x:
			if left[y * town.size.x + x] != both[y * wide.size.x + x] \
					or right[y * town.size.x + x] != both[y * wide.size.x + town.size.x + x]:
				same = false
	_check("two windows side by side across the river meet without a seam", same)

## A chunk's terrain with a one-cell border: its border cells are its neighbour's own, cell for
## cell, and both are the same cells as one area twice as wide.
func _chunk_borders_are_their_neighbours_cells() -> void:
	var region := load(REGION) as WorldLandDef
	var parent := WorldTerrainGenerator.plan(region, 5, CATALOG, ENTITIES)
	var shares := WorldTerrainGenerator.blend_shares(parent, region)
	var points := ((parent["rivers"] as Array)[0] as Dictionary)["points"] as PackedVector2Array
	const SIZE := 32
	var at := (Vector2i(points[points.size() / 2]) * ZOOM / SIZE) * SIZE
	var a := WorldTerrainGenerator.refine_terrain(parent, region, Vector2i(SIZE, SIZE), 2, at, ZOOM, 5, 1, shares)["kinds"] as PackedByteArray
	var b := WorldTerrainGenerator.refine_terrain(parent, region, Vector2i(SIZE, SIZE), 2, at + Vector2i(SIZE, 0), ZOOM, 5, 1, shares)["kinds"] as PackedByteArray
	var both := WorldTerrainGenerator.refine_terrain(parent, region, Vector2i(SIZE * 2, SIZE), 2, at, ZOOM, 5, 0, shares)["kinds"] as PackedByteArray
	var outer := SIZE + 2
	var same := true
	for y in SIZE:
		# A's right border is B's first column, B's left border A's last, and both match the wide area.
		if a[(y + 1) * outer + SIZE + 1] != b[(y + 1) * outer + 1] or b[(y + 1) * outer] != a[(y + 1) * outer + SIZE]:
			same = false
		for x in SIZE:
			if a[(y + 1) * outer + x + 1] != both[y * SIZE * 2 + x] or b[(y + 1) * outer + x + 1] != both[y * SIZE * 2 + SIZE + x]:
				same = false
	_check("a chunk's border cells are its neighbour's, and chunks are one area cut up", same)

## Chunks in view go through every stage before the ring round them, terrain first; what is
## made is kept; drawn chunks far outside the view are offered up to free.
func _chunks_are_made_in_order_and_kept() -> void:
	var chunks := WorldTerrainChunks.new(Vector2i(64, 48), ZOOM, 32)
	var view := Rect2i(Vector2i(160, 96), Vector2i(64, 32))
	var visible := chunks.around(view, 0)
	var order: Array[String] = []
	var done := {WorldTerrainChunks.Stage.TERRAIN: "terrain", WorldTerrainChunks.Stage.DRAW_TERRAIN: "drawn",
		WorldTerrainChunks.Stage.OBJECTS: "nodes", WorldTerrainChunks.Stage.DRAW_OBJECTS: "objects_drawn"}
	for step in 400:
		var job := chunks.next_job(view, 1)
		if job.is_empty():
			break
		var at: Vector2i = job["chunk"]
		if not chunks.chunks.has(at):
			chunks.chunks[at] = {}
		chunks.chunks[at][done[job["stage"]]] = true
		order.append("%s%d" % ["in" if visible.has(at) else "ring", job["stage"]])
	var in_view := visible.size() * 4
	var first := order.slice(0, in_view)
	var staged := first == first.duplicate()
	for k in range(1, first.size()):
		if first[k] < first[k - 1]:
			staged = false
	_check("the %d chunks in view get all four stages, in stage order, before any of the ring" % visible.size(),
		first.all(func(o: String) -> bool: return o.begins_with("in")) and staged and order.size() == chunks.around(view, 1).size() * 4)
	_check("nothing is planned again once made", chunks.next_job(view, 1).is_empty())
	var far := chunks.far(Rect2i(Vector2i(0, 0), Vector2i(32, 32)), 1)
	_check("drawn chunks far from a moved view are offered up to free", far.size() > 0 and not far.has(Vector2i(0, 0)))

## The L3 world, a river into the sea, over several seeds passes WorldTerrainCheck.
func _the_world_is_sound() -> void:
	var world := load(WORLD) as WorldLandDef
	var bad: Array[String] = []
	var usec := 0
	for s in 5:
		var plan := WorldTerrainGenerator.plan(world, s, CATALOG, ENTITIES)
		usec += _sum(plan["usec"])
		var problems := WorldTerrainCheck.problems(world, plan)
		if not problems.is_empty() and bad.is_empty():
			bad = problems
			bad.push_front("seed %d:" % s)
	_check("the L3 world (%dx%d, river to the sea): 5 seeds, every map sound, plan %d ms on average%s" % [world.size.x,
		world.size.y, usec / 5000, "" if bad.is_empty() else "  " + " ".join(bad)], bad.is_empty())

## Regions refined 8x from L3 windows — the one on the river, a corner, the middle — follow the
## world and are sound, and an L1 window on each region's river (or middle) follows the region.
func _regions_follow_the_world_and_l1_follows_them() -> void:
	var world := load(WORLD) as WorldLandDef
	var region := world.child
	var window := region.size / ZOOM
	var land := _land(region, Vector2i(128, 128))
	for s in 3:
		var parent := WorldTerrainGenerator.plan(world, s, CATALOG, ENTITIES)
		var regions := WorldRegions.new(world.size, window)
		var points := ((parent["rivers"] as Array)[0] as Dictionary)["points"] as PackedVector2Array
		var places := {"on the river": regions.region_at(Vector2i(points[points.size() / 2])), "in a corner": Vector2i.ZERO,
			"in the middle": regions.count / 2}
		for name: String in places:
			var at: Vector2i = places[name]
			var origin := at * window
			var started := Time.get_ticks_usec()
			var child := WorldTerrainGenerator.refine(parent, world, region, origin, ZOOM, s, CATALOG, ENTITIES, 1)
			var spent := Time.get_ticks_usec() - started
			var problems := WorldTerrainCheck.follows(parent, world, child, region, origin, ZOOM)
			problems.append_array(WorldTerrainCheck.problems(region, child, true))
			_check("seed %d, region %s %s follows its L3 window and is sound (%d ms)%s" % [s, at, name, spent / 1000,
				"" if problems.is_empty() else "  " + " ".join(problems)], problems.is_empty())
			var lines := child["rivers"] as Array
			var middle := (region.size - land.size / ZOOM) / 2
			if not lines.is_empty():
				var line := (lines[0] as Dictionary)["points"] as PackedVector2Array
				middle = Vector2i(line[line.size() / 2]) - land.size / ZOOM / 2
			var l1_origin := middle.clamp(Vector2i.ZERO, region.size - land.size / ZOOM)
			var l1 := WorldTerrainGenerator.refine(child, region, land, l1_origin, ZOOM, hash([s, at]), CATALOG, ENTITIES)
			problems = WorldTerrainCheck.follows(child, region, l1, land, l1_origin, ZOOM)
			problems.append_array(WorldTerrainCheck.problems(land, l1, true))
			_check("seed %d, an L1 window at %s of region %s (%s) follows it and is sound%s" % [s, l1_origin, at,
				"on its river" if not lines.is_empty() else "no river", "" if problems.is_empty() else "  " + " ".join(problems)],
				problems.is_empty())

## Two regions side by side: each one's border cells are the other's own, so L2 has no seam.
func _neighbouring_regions_meet_without_a_seam() -> void:
	var world := load(WORLD) as WorldLandDef
	var region := world.child
	var window := region.size / ZOOM
	var parent := WorldTerrainGenerator.plan(world, 2, CATALOG, ENTITIES)
	var points := ((parent["rivers"] as Array)[0] as Dictionary)["points"] as PackedVector2Array
	var left_at := WorldRegions.new(world.size, window).region_at(Vector2i(points[points.size() / 2]))
	left_at.x = mini(left_at.x, world.size.x / window.x - 2)
	var a := WorldTerrainGenerator.refine(parent, world, region, left_at * window, ZOOM, 2, CATALOG, ENTITIES, 1)
	var b := WorldTerrainGenerator.refine(parent, world, region, (left_at + Vector2i.RIGHT) * window, ZOOM, 2, CATALOG, ENTITIES, 1)
	var outer_a := a["outer_kinds"] as PackedByteArray
	var outer_b := b["outer_kinds"] as PackedByteArray
	var kinds_a := a["kinds"] as PackedByteArray
	var kinds_b := b["kinds"] as PackedByteArray
	var w := region.size.x
	var outer := w + 2
	var same := true
	for y in region.size.y:
		if outer_a[(y + 1) * outer + w + 1] != kinds_b[y * w] or outer_b[(y + 1) * outer] != kinds_a[y * w + w - 1]:
			same = false
		for x in w:
			if outer_a[(y + 1) * outer + x + 1] != kinds_a[y * w + x]:
				same = false
	_check("regions %s and %s: each one's border cells are the other's own" % [left_at, left_at + Vector2i.RIGHT], same)

## Regions in view are planned before any is drawn, nearest the middle first; nothing is made twice;
## drawn regions far from a moved view are offered up to free.
func _regions_are_made_in_order_and_kept() -> void:
	var regions := WorldRegions.new(Vector2i(128, 96), Vector2i(32, 24))
	var view := Rect2i(Vector2i(40, 20), Vector2i(30, 20))
	var order: Array[int] = []
	for step in 40:
		var job := regions.next_job(view)
		if job.is_empty():
			break
		var at: Vector2i = job["region"]
		if not regions.regions.has(at):
			regions.regions[at] = {}
		regions.regions[at]["plan" if job["stage"] == WorldRegions.Stage.PLAN else "drawn"] = true
		order.append(job["stage"])
	var visible := regions.around(view)
	var sorted := order.duplicate()
	sorted.sort()
	_check("the %d regions in view are planned, then drawn, %s first" % [visible.size(), visible[0]],
		order == sorted and order.size() == visible.size() * 2 and visible[0] == Vector2i(1, 1))
	_check("no region is made twice", regions.next_job(view).is_empty())
	var far := regions.far(Rect2i(Vector2i(100, 80), Vector2i(10, 10)), 0)
	_check("drawn regions far from a moved view are offered up to free", far.size() == visible.size())

## A map through module 10's real pipeline: every command accepted, the grid's terrain the
## plan's, every node born on its cell.
func _a_map_loads_through_the_build_system(key: StringName, def: WorldLandDef, plan: Dictionary) -> void:
	var world := EcsWorld.new()
	var grid := EcsTownGrid.make(def.size.x, def.size.y, CATALOG.terrain_id(&"grass"))
	world.add_singleton(grid)
	world.add_singleton(EcsLifecycleSingleton.new())
	world.add_singleton(EcsTownNavSingleton.new())
	var root := Node.new()
	add_child(root)
	var tiles := Node.new()
	root.add_child(tiles)
	var entities := Node2D.new()
	root.add_child(entities)
	var build := EcsBuildCommandSystem.new(CATALOG, ENTITIES)
	var nav := EcsTownNavSystem.new(CATALOG)
	var sync := EcsTileSyncSystem.new(tiles, CATALOG)
	var systems: Array[EcsSystem] = [EcsLifecycleSystem.new(EcsEntityManager.new(entities), ENTITIES), build, nav, sync]
	var commands := plan["commands"] as Array[EcsBuildCommand]
	grid.commands.append_array(commands)
	var spent: Dictionary = {}
	for tick in 4:
		for system in systems:
			var started := Time.get_ticks_usec()
			system.run(world, 1.0 / 60.0)
			spent[system.label()] = int(spent.get(system.label(), 0)) + Time.get_ticks_usec() - started
	var accepted := 0
	for command in commands:
		if command.result == &"ok":
			accepted += 1
	_check("%s: all %d commands accepted by the build system" % [key, commands.size()], accepted == commands.size())
	var kinds := plan["kinds"] as PackedByteArray
	var same := true
	for i in grid.width * grid.height:
		if grid.terrain[i] != CATALOG.terrain_id(WorldTerrainGenerator.TERRAIN_KEYS[kinds[i]]):
			same = false
			break
	_check("%s: the grid's terrain is the plan's" % key, same)
	var born := true
	for node: Dictionary in plan["nodes"]:
		var cell: Vector2i = node["cell"]
		var id := grid.object_id[EcsTownGrid.index(grid, cell)]
		var on := world.get_component(id, EcsResourceNodeComponent) if id > EcsWorld.NO_ENTITY else null
		if on == null:
			born = false
			break
	_check("%s: every one of its %d nodes is born on its cell" % [key, (plan["nodes"] as Array).size()],
		born and world.query([EcsResourceNodeComponent]).size() == (plan["nodes"] as Array).size())
	print("[terrain]   %s load, 4 ticks: %s" % [key, ", ".join(spent.keys().map(func(k: StringName) -> String: return "%s %d ms" % [k, spent[k] / 1000]))])
	root.free()

func _fingerprint(plan: Dictionary) -> String:
	var parts := PackedStringArray()
	for command: EcsBuildCommand in plan["commands"]:
		parts.append("%d %s %d %s" % [command.kind, command.cell, command.value, command.blueprint])
	return ";".join(parts).md5_text()

func _sum(usec: Dictionary) -> int:
	var total := 0
	for stage in usec:
		total += int(usec[stage])
	return total

## The region's L1 land, `size` cells: what a town's area or a chunk grows.
func _land(region: WorldLandDef, size: Vector2i) -> WorldLandDef:
	var land := region.child.duplicate() as WorldLandDef
	land.size = size
	return land

func _check(what: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
	print("[terrain] %s  %s" % ["ok  " if passed else "FAIL", what])
