class_name EcsTownBuilder
extends RefCounted

## Pure and seeded: a building on every walled plot of a town, from module 10's generator. Each
## plot's role names its building type and may list its rooms; its wealth is the role's, or, when
## the role leaves it to the place, rich by the plaza, middling in the inner ring and poor at the
## edge. The generator builds on the plot's footprint, facing its front, with the entrance at its
## door when that can be one; otherwise the lane is carried along the front to the entrance. The
## commands go into the site's, and each plot gains `building`: {type, wealth, entrance, shape, cells}.
## A plot's field is laid as `def.field_terrain` with `def.field_crop` in rows, a path row between.

const ENTITIES := preload("res://10. Town Generator/defs/entity_catalog.tres")

## Builds every walled plot of `site`; the roles whose building type the catalog lacks.
static func build(site: EcsSettlementSite, def: EcsSettlementDef, catalog: EcsTownCatalog, rng_seed: int,
		progress: EcsProgress = null) -> Array[StringName]:
	var lacking: Array[StringName] = []
	for k in site.plots.size():
		var plot := site.plots[k]
		EcsProgress.say(progress, "Building: %s, %d of %d" % [EcsTownEconomy.CATALOG.role(plot["role"]).display_name, k + 1,
			site.plots.size()], 0.87 + 0.1 * k / site.plots.size())
		if plot.has("field"):
			_sow(site, plot["field"], def, catalog)
		var role := EcsTownEconomy.CATALOG.role(plot["role"])
		if role == null or role.building == &"":
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

## A field: its ground turned to `def.field_terrain`, crops on every other row along its long side.
static func _sow(site: EcsSettlementSite, field: Rect2i, def: EcsSettlementDef, catalog: EcsTownCatalog) -> void:
	var ground := catalog.terrain_id(def.field_terrain)
	var across := field.size.x >= field.size.y
	for y in range(field.position.y, field.end.y):
		for x in range(field.position.x, field.end.x):
			site.commands.append(EcsBuildCommand.make(EcsBuildCommand.Kind.SET_TERRAIN, Vector2i(x, y), ground))
	for y in range(field.position.y, field.end.y):
		for x in range(field.position.x, field.end.x):
			var row := (y - field.position.y) if across else (x - field.position.x)
			if row % 2 == 0:
				site.commands.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, Vector2i(x, y), def.field_crop, 0))

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
