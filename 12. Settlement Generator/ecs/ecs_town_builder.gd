class_name EcsTownBuilder
extends RefCounted

## Pure and seeded: a building on every walled plot of a town, from module 10's generator. Each
## plot's role names its building type and may list its rooms, which a family's list replaces; its wealth is its family's (the
## census's), else the role's, or, when the role leaves it to the place, rich by the plaza,
## middling in the inner ring and poor at the edge. The generator builds on the plot's footprint, facing its front, with the entrance at its
## door when that can be one; otherwise the lane is carried along the front to the entrance. The
## commands go into the site's, and each plot gains `building`: {type, wealth, entrance, shape, cells}.
## A plot's annex: a field (dirt, crop rows, a fence with a gate facing the house, a scarecrow and a
## haystack) or a pen (a fence with a gate, a trough and hay). A dock is a wood floor over water with
## a boat and a mooring post; a watermill's wheel stands on its river. A plot with no walls is laid
## by EcsOutdoorBuilder. A role selling heavy goods keeps a stockpile in its yard by the lane. A
## rich family's house is a walled compound: main house, pavilion and kitchen house. Then the
## dressing: benches and a notice board round the plaza, lamp posts along main roads, and house yards
## fenced and planted by wealth.

const ENTITIES := preload("res://10. Town Generator/defs/entity_catalog.tres")

## Builds every walled plot of `site`; the roles whose building type the catalog lacks.
static func build(site: EcsSettlementSite, def: EcsSettlementDef, catalog: EcsTownCatalog, rng_seed: int,
		progress: EcsProgress = null) -> Array[StringName]:
	var lacking: Array[StringName] = []
	for k in site.plots.size():
		var plot := site.plots[k]
		EcsProgress.say(progress, "Building: %s, %d of %d" % [EcsTownCensus.CATALOG.role(plot["role"]).display_name, k + 1,
			site.plots.size()], 0.87 + 0.1 * k / site.plots.size())
		if plot.has("annex"):
			_annex(site, plot, def, catalog)
		if plot.has("dock"):
			_dock(site, plot["dock"], def, catalog)
		if plot.has("wheel"):
			site.commands.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, plot["wheel"], &"water_wheel", 0))
		var role := EcsTownCensus.CATALOG.role(plot["role"])
		if role == null:
			continue
		if role.building == &"":
			if not EcsOutdoorBuilder.lay(site, plot, def, catalog, hash([rng_seed, site.l2_cell, k])) and not lacking.has(role.key):
				lacking.append(role.key)
			continue
		var type := _type(catalog, role.building)
		if type == null:
			if not lacking.has(role.building):
				lacking.append(role.building)
			continue
		var rooms: Array = plot.get("rooms", role.rooms)
		if not rooms.is_empty():
			type = type.duplicate() as EcsBuildingTypeDef
			type.roles.assign(rooms)
			if plot.has("rooms"):
				type.rooms = [rooms.size()]
		var rect: Rect2i = plot["footprint"]
		var wealth: int = plot.get("wealth", role.wealth)
		if wealth < 0:
			wealth = _wealth_at(site, rect)
		if role.compound and _compound(site, plot, type, wealth, catalog, hash([rng_seed, site.l2_cell, k])):
			continue
		var plan := EcsBuildingGenerator.plan(type, rect.size, wealth, plot["front"], hash([rng_seed, site.l2_cell, k]),
			catalog, ENTITIES, rect.position, plot["door"])
		site.commands.append_array(plan["commands"])
		plot["building"] = {"type": type.key, "wealth": wealth, "entrance": plan["entrance"], "shape": plan["shape"],
			"cells": plan["cells"]}
		if plan["entrance"] != plot["door"] and plan["entrance"] != Vector2i(-1, -1):
			_carry_lane(site, plot["door"] + plot["front"], plan["entrance"] + plot["front"])
			plot["door"] = plan["entrance"]
		if role.stockpile != &"":
			_stockpile(site, plot, role.stockpile)
	for plot in site.plots:
		_keep_joined(site, plot)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([rng_seed, site.l2_cell, &"dressing"])
	_dress_plaza(site, def)
	_lamp_posts(site, def)
	for plot in site.plots:
		var role := EcsTownCensus.CATALOG.role(plot["role"])
		if role != null and role.home >= 0 and role.home <= 1:
			_dress_yard(site, plot, def, rng)
	return lacking

## Benches round the plaza's edge, along it, one every `bench_every` cells, and a notice board; the
## well's ring, the cells where a road meets the plaza and those before a door are kept clear.
static func _dress_plaza(site: EcsSettlementSite, def: EcsSettlementDef) -> void:
	var keep: Dictionary = {}
	for plot in site.plots:
		keep[plot["door"] + plot["front"]] = true
	var plaza := site.plaza
	for cell in EcsBuildRules.cells(plaza):
		if Vector2(cell).distance_to(Vector2(site.well)) <= 2.5:
			keep[cell] = true
		for side in EcsPlotPlanner.SIDES:
			if site.road_cells.has(cell + side) and not plaza.has_point(cell + side):
				for k in range(-2, 3):
					keep[cell + Vector2i(side.y, side.x) * k] = true
	var placed := 0
	var board := false
	for side in EcsPlotPlanner.SIDES:
		var along := Vector2i(absi(side.y), absi(side.x))
		var edge := Vector2i(plaza.end.x - 1 if side.x > 0 else plaza.position.x, plaza.end.y - 1 if side.y > 0 else plaza.position.y)
		var start := Vector2i(plaza.position.x if along.x != 0 else edge.x, plaza.position.y if along.y != 0 else edge.y)
		var length := plaza.size.x if along.x != 0 else plaza.size.y
		for k in range(2, length - 3, def.bench_every):
			var cell := start + along * k
			if keep.has(cell) or keep.has(cell + along):
				continue
			if not board:
				site.commands.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, cell, &"notice_board", 0))
				keep[cell] = true
				board = true
				continue
			site.commands.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, cell, &"bench", 0 if along.x != 0 else 1))
			keep[cell] = true
			keep[cell + along] = true
			placed += 1
	site.economy["benches"] = placed

## A lamp post on the verge every `lamp_every` cells of main road within the town's radius, on a cell no road,
## plot or yard holds.
static func _lamp_posts(site: EcsSettlementSite, def: EcsSettlementDef) -> void:
	var lamps := 0
	for road in site.roads:
		if road["kind"] != &"main":
			continue
		var points := road["points"] as PackedVector2Array
		var walked := 0.0
		for k in range(1, points.size()):
			walked += points[k].distance_to(points[k - 1])
			if walked < def.lamp_every:
				continue
			var normal := (points[k] - points[k - 1]).normalized().orthogonal()
			for sign in [1.0, -1.0]:
				var cell := Vector2i((points[k] + normal * sign * (def.main_width / 2.0 + 1.0)).round())
				if Vector2(cell).distance_to(Vector2(site.well)) > site.radius or not site.area.has_point(cell) or site.road_cells.has(cell) or site.plot_at.has(cell) \
						or site.plaza.grow(1).has_point(cell):
					continue
				site.commands.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, cell, &"lamp_post", 0))
				site.plot_at[cell] = -1
				lamps += 1
				walked = 0.0
				break
	for cell: Vector2i in site.plot_at.keys():
		if site.plot_at[cell] == -1:
			site.plot_at.erase(cell)
	site.economy["lamps"] = lamps

## A house's yard by its wealth: maybe a fence round its outer cells, open by the lane, and inside a
## garden bed, a chicken coop and a banana tree, each by chance; none on the cells by the door.
static func _dress_yard(site: EcsSettlementSite, plot: Dictionary, def: EcsSettlementDef, rng: RandomNumberGenerator) -> void:
	var wealth: int = clampi(plot.get("wealth", 0), 0, 2)
	var yard: Dictionary = {}
	for cell: Vector2i in plot["yard"]:
		yard[cell] = true
	if yard.size() < 6:
		return
	var rect: Rect2i = plot["footprint"]
	var lane: Vector2i = plot["door"] + plot["front"]
	var free: Dictionary = yard.duplicate()
	free.erase(plot.get("stockpile", Vector2i(-1, -1)))
	for cell: Vector2i in yard:
		if Vector2(cell).distance_to(Vector2(lane)) < 2.5 or Vector2(cell).distance_to(Vector2(plot["door"])) < 2.5:
			free.erase(cell)
	if rng.randf() < def.yard_fence[wealth]:
		var ring: Array[Vector2i] = []
		for cell: Vector2i in free:
			for side in EcsPlotPlanner.SIDES:
				var next: Vector2i = cell + side
				if not yard.has(next) and not rect.has_point(next):
					ring.append(cell)
					break
		for cell in ring:
			var across := yard.has(cell + Vector2i.LEFT) or yard.has(cell + Vector2i.RIGHT)
			site.commands.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, cell, &"fence", 0 if across else 1))
			free.erase(cell)
		plot["fenced"] = true
	var inner: Array = free.keys()
	inner.sort()
	for pick in [[&"garden_bed", def.yard_garden, Vector2i(2, 1)], [&"chicken_coop", def.yard_coop, Vector2i.ONE],
			[&"banana_tree", def.yard_tree, Vector2i.ONE]]:
		if rng.randf() >= (pick[1] as Array)[wealth]:
			continue
		var size: Vector2i = pick[2]
		for attempt in 12:
			if inner.is_empty():
				break
			var at: Vector2i = inner[rng.randi_range(0, inner.size() - 1)]
			var cells := EcsBuildRules.cells(Rect2i(at, size))
			if cells.all(func(c: Vector2i) -> bool: return free.has(c)):
				site.commands.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, at, pick[0], 0))
				for c in cells:
					free.erase(c)
					inner.erase(c)
				break

## A walled compound on `plot`: a fence round it with its gate at the door, the main house of
## `type` across the back facing the gate, and in front of it, either side of a clear way in, an
## open pavilion (posts and a wood floor, no roof yet) and a kitchen house facing the way in, when
## there is room. False when the plot is too small, so it is built as one house.
static func _compound(site: EcsSettlementSite, plot: Dictionary, type: EcsBuildingTypeDef, wealth: int,
		catalog: EcsTownCatalog, rng_seed: int) -> bool:
	var rect: Rect2i = plot["footprint"]
	var front: Vector2i = plot["front"]
	var size := rect.size
	var across := size.x if front.y != 0 else size.y
	var depth := size.y if front.y != 0 else size.x
	var door_u := -1
	for u in across:
		if EcsBuildingGenerator._frame_cell(Vector2i(u, 0), size, front) + rect.position == plot["door"]:
			door_u = u
	var main_d := clampi(roundi((depth - 2) * 0.6), 6, depth - 2)
	var yard_d := depth - 2 - main_d
	if door_u < 3 or door_u > across - 4 or across < 12 or yard_d < 1:
		return false
	var local := func(frame: Rect2i) -> Rect2i:
		var r := EcsBuildingGenerator._from_frame(frame, size, front)
		return Rect2i(r.position + rect.position, r.size)
	var gate: Array[Vector2i] = [plot["door"], EcsBuildingGenerator._frame_cell(Vector2i(door_u + 1, 0), size, front) + rect.position]
	for cell in EcsBuildRules.cells(rect):
		if rect.grow(-1).has_point(cell) or gate.has(cell):
			continue
		var turns := 0 if cell.y == rect.position.y or cell.y == rect.end.y - 1 else 1
		site.commands.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, cell, &"fence", turns))
	var v0 := depth - 1 - main_d
	var outbuildings: Array = []
	var kitchen := false
	# Either side of the way in: the pavilion left, the kitchen house right.
	var side_d := mini(yard_d - 1, 5)
	var left_w := mini(door_u - 2, 6)
	var right_w := mini(across - 2 - (door_u + 3), 6)
	if side_d >= 4 and right_w >= 5:
		var hut := _type(catalog, &"hut")
		if hut != null:
			hut = hut.duplicate() as EcsBuildingTypeDef
			hut.roles.assign([&"kitchen"])
			hut.rooms = [1]
			var r: Rect2i = local.call(Rect2i(door_u + 3, v0 - 1 - side_d, right_w, side_d))
			var toward := EcsBuildingGenerator._frame_cell(Vector2i(door_u + 4, 1), size, front) \
				- EcsBuildingGenerator._frame_cell(Vector2i(door_u + 5, 1), size, front)
			var plan := EcsBuildingGenerator.plan(hut, r.size, wealth, toward, rng_seed + 1, catalog, ENTITIES, r.position)
			site.commands.append_array(plan["commands"])
			outbuildings.append({"type": hut.key, "entrance": plan["entrance"], "rect": r})
			kitchen = plan["entrance"] != Vector2i(-1, -1)
	if side_d >= 3 and left_w >= 4:
		var r: Rect2i = local.call(Rect2i(door_u - 1 - left_w, v0 - 1 - side_d, left_w, side_d))
		var wood := catalog.floor_id(&"wood")
		for cell in EcsBuildRules.cells(r):
			site.commands.append(EcsBuildCommand.make(EcsBuildCommand.Kind.SET_FLOOR, cell, wood))
		for corner in [r.position, Vector2i(r.end.x - 1, r.position.y), Vector2i(r.position.x, r.end.y - 1), r.end - Vector2i.ONE]:
			site.commands.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, corner, &"stump", 0))
		outbuildings.append({"type": &"pavilion", "rect": r})
	var house := type
	if kitchen and type.roles.has(&"kitchen"):
		house = type.duplicate() as EcsBuildingTypeDef
		house.roles.erase(&"kitchen")
		house.rooms = [house.roles.size()]
	var main: Rect2i = local.call(Rect2i(1, v0, across - 2, main_d))
	var door: Vector2i = EcsBuildingGenerator._frame_cell(Vector2i(door_u, v0), size, front) + rect.position
	var plan := EcsBuildingGenerator.plan(house, main.size, wealth, front, rng_seed, catalog, ENTITIES, main.position, door)
	site.commands.append_array(plan["commands"])
	plot["building"] = {"type": house.key, "wealth": wealth, "entrance": plan["entrance"], "shape": &"compound",
		"cells": plan["cells"], "at": main.position, "gate": plot["door"]}
	plot["outbuildings"] = outbuildings
	return true

## A stockpile of heavy goods in the yard, on the free yard cell nearest the lane at the door.
static func _stockpile(site: EcsSettlementSite, plot: Dictionary, blueprint: StringName) -> void:
	var lane: Vector2i = plot["door"] + plot["front"]
	var best := Vector2i(-1, -1)
	for cell: Vector2i in plot["yard"]:
		if site.road_cells.has(cell) or cell == lane:
			continue
		if best == Vector2i(-1, -1) or Vector2(cell).distance_squared_to(Vector2(lane)) < Vector2(best).distance_squared_to(Vector2(lane)):
			best = cell
	if best != Vector2i(-1, -1):
		site.commands.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, best, blueprint, 0))
		plot["stockpile"] = best

## Drops the yard cells a carried lane cut off from their plot's footprint.
static func _keep_joined(site: EcsSettlementSite, plot: Dictionary) -> void:
	var yard: Dictionary = {}
	for cell: Vector2i in plot["yard"]:
		yard[cell] = true
	var rect: Rect2i = plot["footprint"]
	var reached: Dictionary = {}
	var stack: Array[Vector2i] = []
	for cell in EcsBuildRules.cells(rect):
		stack.append(cell)
	while not stack.is_empty():
		var at: Vector2i = stack.pop_back()
		for side in EcsPlotPlanner.SIDES:
			var next := at + side
			if yard.has(next) and not reached.has(next):
				reached[next] = true
				stack.append(next)
	if reached.size() == yard.size():
		return
	var kept: Array[Vector2i] = []
	for cell: Vector2i in plot["yard"]:
		if reached.has(cell):
			kept.append(cell)
		else:
			site.plot_at.erase(cell)
	plot["yard"] = kept

## A plot's field or pen: fenced round its edge with a 2-cell gate on the side facing the house;
## a field is dirt with a scarecrow at its middle, a haystack in a corner and crops on every other
## row along its long side; a pen holds a trough and hay.
static func _annex(site: EcsSettlementSite, plot: Dictionary, def: EcsSettlementDef, catalog: EcsTownCatalog) -> void:
	var annex: Rect2i = plot["annex"]
	var field: bool = plot["annex_kind"] == &"field"
	var home := Vector2((plot["footprint"] as Rect2i).get_center() - annex.get_center())
	var facing := Vector2i(signi(roundi(home.x)), 0) if absf(home.x) >= absf(home.y) else Vector2i(0, signi(roundi(home.y)))
	var gate := _gate(annex, facing)
	if field:
		var ground := catalog.terrain_id(def.field_terrain)
		for cell in EcsBuildRules.cells(annex):
			site.commands.append(EcsBuildCommand.make(EcsBuildCommand.Kind.SET_TERRAIN, cell, ground))
	var inside := annex.grow(-1)
	for cell in EcsBuildRules.cells(annex):
		if inside.has_point(cell) or gate.has(cell):
			continue
		# Rails along the top and bottom rows run across, the sides' run down.
		var turns := 0 if cell.y == annex.position.y or cell.y == annex.end.y - 1 else 1
		site.commands.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, cell, &"fence", turns))
	var taken: Dictionary = {}
	# The cells inside the gate stay clear, so the way in is never blocked.
	for cell: Vector2i in gate:
		taken[cell - facing] = true
	if field:
		var middle := inside.position + inside.size / 2
		var corner := inside.position if not taken.has(inside.position) else inside.end - Vector2i.ONE
		for pair in [[middle, &"scarecrow"], [corner, &"haystack"]]:
			if not taken.has(pair[0]):
				site.commands.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, pair[0], pair[1], 0))
				taken[pair[0]] = true
		var across := inside.size.x >= inside.size.y
		for cell in EcsBuildRules.cells(inside):
			var row := (cell.y - inside.position.y) if across else (cell.x - inside.position.x)
			if row % 2 == 0 and not taken.has(cell):
				site.commands.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, cell, def.field_crop, 0))
	else:
		var trough := (inside.position + inside.size / 2 - facing * (maxi(inside.size.x, inside.size.y) / 3)).clamp(inside.position, inside.end - Vector2i(2, 1))
		site.commands.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, trough, &"trough", 0))
		var hay := inside.end - Vector2i.ONE
		if not taken.has(hay) and not Rect2i(trough, Vector2i(2, 1)).has_point(hay):
			site.commands.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, hay, &"hay_pile", 0))

## The 2 cells in the middle of `annex`'s side facing `facing`, left open as its gate.
static func _gate(annex: Rect2i, facing: Vector2i) -> Array[Vector2i]:
	var mid := annex.position + annex.size / 2
	var edge := Vector2i(annex.end.x - 1 if facing.x > 0 else annex.position.x, annex.end.y - 1 if facing.y > 0 else annex.position.y)
	if facing.x != 0:
		return [Vector2i(edge.x, mid.y - 1), Vector2i(edge.x, mid.y)]
	return [Vector2i(mid.x - 1, edge.y), Vector2i(mid.x, edge.y)]

## A dock: wood floor on its cells, the boat moored past its end, a post on it.
static func _dock(site: EcsSettlementSite, dock: Dictionary, def: EcsSettlementDef, catalog: EcsTownCatalog) -> void:
	var wood := catalog.floor_id(def.bridge_floor)
	for cell: Vector2i in dock["cells"]:
		site.commands.append(EcsBuildCommand.make(EcsBuildCommand.Kind.SET_FLOOR, cell, wood))
	site.commands.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, dock["post"], &"mooring_post", 0))
	if dock["boat"] != Vector2i(-1, -1):
		site.commands.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, dock["boat"], &"boat", dock["boat_turns"]))

static func _type(catalog: EcsTownCatalog, key: StringName) -> EcsBuildingTypeDef:
	for type in catalog.building_types:
		if type.key == key:
			return type
	return null

## 2 by the plaza, 1 in the inner ring, 0 at the edge: the `centre` rule at ⅔ and ⅓.
static func _wealth_at(site: EcsSettlementSite, rect: Rect2i) -> int:
	var near := 1.0 - clampf(Vector2(rect.get_center()).distance_to(Vector2(site.well)) / maxf(site.radius, 1.0), 0.0, 1.0)
	return 2 if near >= 2.0 / 3.0 else (1 if near >= 1.0 / 3.0 else 0)

## Lane cells along a plot's front, from the cell before its door to the one before its entrance;
## a yard cell they take leaves its plot's yard.
static func _carry_lane(site: EcsSettlementSite, from: Vector2i, to: Vector2i) -> void:
	var step := (to - from).sign()
	var at := from
	while true:
		if not site.road_cells.has(at):
			site.road_cells[at] = &"lane"
			site.cleared_cells[at] = true
			if site.plot_at.has(at):
				(site.plots[site.plot_at[at]]["yard"] as Array).erase(at)
				site.plot_at.erase(at)
		if at == to:
			break
		at += step
