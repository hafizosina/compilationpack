class_name EcsTownBuilder
extends RefCounted

## Pure and seeded: a building on every walled plot of a town, from module 10's generator. Each
## plot's role names its building type and may list its rooms; its wealth is the role's, or, when
## the role leaves it to the place, rich by the plaza, middling in the inner ring and poor at the
## edge. The generator builds on the plot's footprint, facing its front, with the entrance at its
## door when that can be one; otherwise the lane is carried along the front to the entrance. The
## commands go into the site's, and each plot gains `building`: {type, wealth, entrance, shape, cells}.
## A plot's annex: a field (dirt, crop rows, a fence with a gate facing the house, a scarecrow and a
## haystack) or a pen (a fence with a gate, a trough and hay). A dock is a wood floor over water with
## a boat and a mooring post; a watermill's wheel stands on its river. A plot with no walls is laid
## by EcsOutdoorBuilder.

const ENTITIES := preload("res://10. Town Generator/defs/entity_catalog.tres")

## Builds every walled plot of `site`; the roles whose building type the catalog lacks.
static func build(site: EcsSettlementSite, def: EcsSettlementDef, catalog: EcsTownCatalog, rng_seed: int,
		progress: EcsProgress = null) -> Array[StringName]:
	var lacking: Array[StringName] = []
	for k in site.plots.size():
		var plot := site.plots[k]
		EcsProgress.say(progress, "Building: %s, %d of %d" % [EcsTownEconomy.CATALOG.role(plot["role"]).display_name, k + 1,
			site.plots.size()], 0.87 + 0.1 * k / site.plots.size())
		if plot.has("annex"):
			_annex(site, plot, def, catalog)
		if plot.has("dock"):
			_dock(site, plot["dock"], def, catalog)
		if plot.has("wheel"):
			site.commands.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, plot["wheel"], &"water_wheel", 0))
		var role := EcsTownEconomy.CATALOG.role(plot["role"])
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
		if not role.rooms.is_empty():
			type = type.duplicate() as EcsBuildingTypeDef
			type.roles = role.rooms.duplicate()
		var rect: Rect2i = plot["footprint"]
		var wealth := role.wealth if role.wealth >= 0 else _wealth_at(site, rect)
		var plan := EcsBuildingGenerator.plan(type, rect.size, wealth, plot["front"], hash([rng_seed, site.l2_cell, k]),
			catalog, ENTITIES, rect.position, plot["door"])
		site.commands.append_array(plan["commands"])
		plot["building"] = {"type": type.key, "wealth": wealth, "entrance": plan["entrance"], "shape": plan["shape"],
			"cells": plan["cells"]}
		if plan["entrance"] != plot["door"] and plan["entrance"] != Vector2i(-1, -1):
			_carry_lane(site, plot["door"] + plot["front"], plan["entrance"] + plot["front"])
			plot["door"] = plan["entrance"]
	for plot in site.plots:
		_keep_joined(site, plot)
	return lacking

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
	var half := Vector2(site.area.size).length() * 0.5
	var near := 1.0 - clampf(Vector2(rect.get_center()).distance_to(Vector2(site.well)) / half, 0.0, 1.0)
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
