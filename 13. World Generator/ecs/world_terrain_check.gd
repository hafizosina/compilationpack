class_name WorldTerrainCheck
extends RefCounted

## Pure: what is wrong with a generated map, read off WorldTerrainGenerator's plan; empty when
## sound. The water is one body (a river reaches both edges), each share is near the def's,
## every node kind has its count and stands in its zone, and nodes never wall off any land.
## `follows` checks a refined child against its parent.

## How far a share may stray from the def's, as a fraction of it.
const SHARE_TOLERANCE: float = 0.25
## Walkable land in one piece, per land area cut off by water, at least this share.
const OPEN_SHARE: float = 0.95
## Land areas smaller than this (islets) aren't held to OPEN_SHARE.
const MIN_LAND_AREA: int = 50
## A child's blocks whose most common kind is its parent cell's, at least this share.
const FOLLOW_SHARE: float = 0.9

## `refined`: a child of a refine, whose water, shares and counts are its parent's; only its
## nodes' zones and the land staying open are checked (`follows` checks the rest).
static func problems(def: WorldLandDef, plan: Dictionary, refined: bool = false) -> Array[String]:
	var out: Array[String] = []
	if refined:
		out.append_array(_out_of_zone(def, plan))
		out.append_array(_walled_off(def, plan))
		return out
	var w := def.size.x
	var h := def.size.y
	var kinds := plan["kinds"] as PackedByteArray
	var counts := [0, 0, 0, 0, 0]
	for i in w * h:
		counts[kinds[i]] += 1
	var water := PackedByteArray()
	water.resize(w * h)
	for i in w * h:
		water[i] = 1 if kinds[i] == WorldTerrainGenerator.WATER else 0
	var bodies := WorldTerrainGenerator.areas(water, w, h)
	var body_count := (bodies[1] as PackedInt32Array).size() - 1
	if def.water == WorldLandDef.Water.RIVER:
		if not _spans(bodies[0], w, h):
			out.append("the river doesn't reach both edges")
	elif body_count != 1:
		out.append("water is %d bodies, not one" % body_count)
	if def.water == WorldLandDef.Water.RIVER_TO_SEA and not _touches(kinds, w, h, -(plan["coast_side"] as Vector2i)):
		out.append("the river doesn't reach the edge across from the sea")
	var shares := {"water": [WorldTerrainGenerator.WATER, def.water_share], "rock": [WorldTerrainGenerator.ROCK, def.rock_share],
		"forest": [WorldTerrainGenerator.FOREST, def.forest_share]}
	for name: String in shares:
		if name == "water" and def.water != WorldLandDef.Water.LAKE and def.water != WorldLandDef.Water.COAST:
			continue
		var want: float = shares[name][1]
		var got := float(counts[shares[name][0]]) / (w * h)
		if absf(got - want) > want * SHARE_TOLERANCE:
			out.append("%s is %.1f%% of the map, not %.1f%%" % [name, got * 100.0, want * 100.0])
	var wanted: Dictionary = {}
	for spawn in def.nodes:
		wanted[spawn.blueprint] = int(wanted.get(spawn.blueprint, 0)) + spawn.min_count
	for blueprint: StringName in wanted:
		var got := int((plan["counts"] as Dictionary).get(blueprint, 0))
		if got < wanted[blueprint]:
			out.append("%d %s, fewer than %d" % [got, blueprint, wanted[blueprint]])
	out.append_array(_out_of_zone(def, plan))
	out.append_array(_walled_off(def, plan))
	return out

## What is wrong with `child`, refined `scale` times from `parent`'s cells at `origin`: every
## parent cell whose whole neighbourhood is one kind has a child block all of that kind, and
## nearly every block's most common kind is its parent cell's.
static func follows(parent: Dictionary, parent_def: WorldLandDef, child: Dictionary, def: WorldLandDef,
		origin: Vector2i, scale: int) -> Array[String]:
	var pw := parent_def.size.x
	var ph := parent_def.size.y
	var parent_kinds := parent["kinds"] as PackedByteArray
	var kinds := child["kinds"] as PackedByteArray
	var w := def.size.x
	var blocks := def.size / scale
	var followed := 0
	var out: Array[String] = []
	for by in blocks.y:
		for bx in blocks.x:
			var cell := origin + Vector2i(bx, by)
			var kind := parent_kinds[cell.y * pw + cell.x]
			var tally := [0, 0, 0, 0, 0]
			for y in scale:
				for x in scale:
					tally[kinds[(by * scale + y) * w + bx * scale + x]] += 1
			if tally.find(tally.max()) == kind:
				followed += 1
			if tally[kind] != scale * scale and _whole_neighbourhood(parent_kinds, pw, ph, cell, kind) and out.is_empty():
				out.append("the block under %s (all %s round it) isn't all %s" % [cell,
					WorldTerrainGenerator.TERRAIN_KEYS[kind], WorldTerrainGenerator.TERRAIN_KEYS[kind]])
	var share := float(followed) / (blocks.x * blocks.y)
	if share < FOLLOW_SHARE:
		out.append("only %.0f%% of blocks follow their parent cell" % (share * 100.0))
	return out

static func _whole_neighbourhood(kinds: PackedByteArray, w: int, h: int, cell: Vector2i, kind: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var x := clampi(cell.x + dx, 0, w - 1)
			var y := clampi(cell.y + dy, 0, h - 1)
			if kinds[y * w + x] != kind:
				return false
	return true

## True when water touches the map's `side` edge.
static func _touches(kinds: PackedByteArray, w: int, h: int, side: Vector2i) -> bool:
	var count := h if side.x != 0 else w
	for k in count:
		var x := (w - 1 if side.x > 0 else 0) if side.x != 0 else k
		var y := (h - 1 if side.y > 0 else 0) if side.y != 0 else k
		if kinds[y * w + x] == WorldTerrainGenerator.WATER:
			return true
	return false

## True when one water body touches both edges the river runs between.
static func _spans(label: PackedInt32Array, w: int, h: int) -> bool:
	var across := w >= h
	var near: Dictionary = {}
	var count := h if across else w
	for k in count:
		var i := k * w if across else k
		if label[i] != 0:
			near[label[i]] = true
	for k in count:
		var i := k * w + w - 1 if across else (h - 1) * w + k
		if label[i] != 0 and near.has(label[i]):
			return true
	return false

static func _out_of_zone(def: WorldLandDef, plan: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var zones := plan["zones"] as PackedByteArray
	var zone_of: Dictionary = {}
	for spawn in def.nodes:
		zone_of[spawn.blueprint] = zone_of.get(spawn.blueprint, 0) | (1 << spawn.zone)
	for node: Dictionary in plan["nodes"]:
		var cell: Vector2i = node["cell"]
		if not (zones[cell.y * def.size.x + cell.x] & int(zone_of.get(node["blueprint"], 0))):
			out.append("%s at %s is out of its zone" % [node["blueprint"], cell])
			break
	return out

## Each land area (cut off by water) keeps OPEN_SHARE of its walkable cells in one piece.
static func _walled_off(def: WorldLandDef, plan: Dictionary) -> Array[String]:
	var w := def.size.x
	var h := def.size.y
	var kinds := plan["kinds"] as PackedByteArray
	var land := PackedByteArray()
	land.resize(w * h)
	for i in w * h:
		land[i] = 0 if kinds[i] == WorldTerrainGenerator.WATER else 1
	var open := land.duplicate()
	for node: Dictionary in plan["nodes"]:
		var cell: Vector2i = node["cell"]
		var size: Vector2i = node["size"]
		for dy in size.y:
			for dx in size.x:
				open[(cell.y + dy) * w + cell.x + dx] = 0
	var lands := WorldTerrainGenerator.areas(land, w, h)
	var land_label := lands[0] as PackedInt32Array
	var land_size := lands[1] as PackedInt32Array
	var pieces := WorldTerrainGenerator.areas(open, w, h)
	var piece_label := pieces[0] as PackedInt32Array
	var piece_size := pieces[1] as PackedInt32Array
	var walkable: Dictionary = {}
	var best: Dictionary = {}
	for i in w * h:
		if piece_label[i] == 0:
			continue
		var area := land_label[i]
		walkable[area] = int(walkable.get(area, 0)) + 1
		best[area] = maxi(int(best.get(area, 0)), piece_size[piece_label[i]])
	var out: Array[String] = []
	for area: int in walkable:
		if land_size[area] >= MIN_LAND_AREA and float(best[area]) / walkable[area] < OPEN_SHARE:
			out.append("nodes wall off %.0f%% of a land area" % ((1.0 - float(best[area]) / walkable[area]) * 100.0))
	return out
