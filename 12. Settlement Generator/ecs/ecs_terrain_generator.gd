class_name EcsTerrainGenerator
extends RefCounted

## Pure and seeded: a settlement map's ground and resource nodes, given back as module 10 build
## commands (SET_TERRAIN, then PLACE_OBJECT). The same def and seed always give the same commands.
## `plan` makes a whole map (an L2 region, or an L1 map on its own):
##   1. Water: a lake, a river edge to edge, a coast along one side, or a river into the sea.
##   2. Shore: land near the water becomes sand.
##   3. Rock: blobs of rocky ground away from the water.
##   4. Forest: the rest of the land, by noise.
##   5. Nodes: each spawn def scattered or clumped over its zone, in def order.
## `refine` zooms into a window of a parent plan: the child adds detail but never contradicts it.
## Every stage has its own seed, so changing one stage leaves the others as they were.

## What each cell is, in `kinds`.
const GRASS: int = 0
const WATER: int = 1
const SAND: int = 2
const ROCK: int = 3
const FOREST: int = 4
const KIND_COUNT: int = 5
## Terrain keys by kind; grass is the base and sends no command.
const TERRAIN_KEYS: Array[StringName] = [&"grass", &"water", &"sand", &"rock", &"forest"]
## Rock blobs smaller than this go back to grass.
const MIN_ROCK_BLOB: int = 12
## Forest within this many cells of its edge is FOREST_EDGE; this far in or more, DEEP_FOREST.
const EDGE_DEPTH: int = 2
const DEEP_DEPTH: int = 4
const SIDES: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
## How far a refine's detail noise may push a kind's blended share, either way. Under 0.5, so a
## cell whose parent neighbourhood is all one kind can never turn into another.
const DETAIL: float = 0.3
## How far a refined river's centre wanders from its parent's line, in child cells.
const RIVER_JITTER: float = 1.5
## Child cells worked round a refined area, then cropped: past the shore width, the jitter and the
## deepest zone distance, so cells near the edge get the same zones as in a bigger area.
const MARGIN: int = 5

## The map for `def` and `rng_seed`: {commands, kinds, zones (bit per EcsNodeSpawnDef.Zone),
## nodes: [{blueprint, cell, size}], counts: {blueprint: n}, rivers: [{points, radii}],
## river (1 per cell a river made water), coast_side, usec: {stage: µs}}.
static func plan(def: EcsSettlementDef, rng_seed: int, catalog: EcsTownCatalog, entities: EcsEntityCatalog) -> Dictionary:
	var w := def.size.x
	var h := def.size.y
	var kinds := PackedByteArray()
	kinds.resize(w * h)
	var river := PackedByteArray()
	river.resize(w * h)
	var rivers: Array[Dictionary] = []
	var coast_side := Vector2i.ZERO
	var usec: Dictionary = {}
	var started := Time.get_ticks_usec()
	var rng := _rng(rng_seed, 1)
	match def.water:
		EcsSettlementDef.Water.LAKE:
			_lake(def, kinds, rng)
		EcsSettlementDef.Water.RIVER:
			rivers.append(_river(def, kinds, river, rng, w >= h))
		EcsSettlementDef.Water.COAST:
			coast_side = _coast(def, kinds, rng)
		EcsSettlementDef.Water.RIVER_TO_SEA:
			coast_side = _coast(def, kinds, rng)
			rivers.append(_river(def, kinds, river, rng, coast_side.x != 0))
	usec["water"] = _lap(started)
	started = Time.get_ticks_usec()
	var from_water := distance_from(kinds, w, h, WATER, false)
	for i in w * h:
		if kinds[i] == GRASS and from_water[i] <= def.shore_width:
			kinds[i] = SAND
	usec["shore"] = _lap(started)
	started = Time.get_ticks_usec()
	_rock(def, kinds, from_water, _rng(rng_seed, 2))
	usec["rock"] = _lap(started)
	started = Time.get_ticks_usec()
	_forest(def, kinds, _rng(rng_seed, 3))
	usec["forest"] = _lap(started)
	var out := _finish(def, kinds, PackedByteArray(), _rng(rng_seed, 4), catalog, entities, usec)
	out["rivers"] = rivers
	out["river"] = river
	out["coast_side"] = coast_side
	return out

## A child map of `def`'s size zoomed `scale` times into `parent`'s cells from `origin`: its
## terrain (`refine_terrain`), then nodes and commands as in `plan`. Neighbouring windows meet
## without a seam.
static func refine(parent: Dictionary, parent_def: EcsSettlementDef, def: EcsSettlementDef, origin: Vector2i,
		scale: int, rng_seed: int, catalog: EcsTownCatalog, entities: EcsEntityCatalog) -> Dictionary:
	var terrain := refine_terrain(parent, parent_def, def.size, def.shore_width, origin * scale, scale, rng_seed)
	var usec := terrain["usec"] as Dictionary
	var out := _finish(def, terrain["kinds"], terrain["zones"], _rng(hash([rng_seed, origin]), 7), catalog, entities, usec)
	out["rivers"] = []
	out["river"] = terrain["river"]
	out["coast_side"] = parent["coast_side"]
	return out

## A child's ground only, `size` cells from child cell `at` (`scale` child cells a parent cell):
## the parent's kinds blended up with detail noise, its rivers redrawn along their own lines so
## they run smooth, then the shore. Noise is read in whole-map coordinates and the work is done
## MARGIN cells wider each side, so any two areas agree cell for cell where they overlap.
## {kinds, river: with `border` cells round `size`, zones: `size` only, usec}. `shares` is
## `blend_shares(parent, …)` when the caller keeps it, else it is made here.
static func refine_terrain(parent: Dictionary, parent_def: EcsSettlementDef, size: Vector2i, shore_width: int,
		at: Vector2i, scale: int, rng_seed: int, border: int = 0, shares: Array = []) -> Dictionary:
	var pw := parent_def.size.x
	var ph := parent_def.size.y
	var pad := border + MARGIN
	var w := size.x + pad * 2
	var h := size.y + pad * 2
	var base := at - Vector2i(pad, pad)
	var usec: Dictionary = {}
	var started := Time.get_ticks_usec()
	if shares.is_empty():
		shares = blend_shares(parent, parent_def)
	var detail: Array[PackedByteArray] = []
	var noise_rng := _rng(rng_seed, 5)
	for kind in KIND_COUNT:
		var noise := _noise(noise_rng, 0.08)
		noise.offset = Vector3(base.x, base.y, 0)
		detail.append(noise.get_image(w, h, false, false, false).get_data())
	var kinds := PackedByteArray()
	kinds.resize(w * h)
	for i in w * h:
		var p := (Vector2(base) + Vector2((i % w) + 0.5, (i / w) + 0.5)) / scale - Vector2(0.5, 0.5)
		var best := GRASS
		var best_score := -INF
		for kind in KIND_COUNT:
			var score := _blend(shares[kind], pw, ph, p) + (detail[kind][i] / 255.0 * 2.0 - 1.0) * DETAIL
			if score > best_score:
				best_score = score
				best = kind
		kinds[i] = best
	usec["blend"] = _lap(started)
	started = Time.get_ticks_usec()
	var river := PackedByteArray()
	river.resize(w * h)
	var jitter := _noise(_rng(rng_seed, 6), 0.05)
	for line: Dictionary in parent["rivers"]:
		_redraw(line, base, scale, kinds, river, w, h, jitter)
	usec["river"] = _lap(started)
	started = Time.get_ticks_usec()
	var from_water := distance_from(kinds, w, h, WATER, false)
	for i in w * h:
		if kinds[i] == GRASS and from_water[i] <= shore_width:
			kinds[i] = SAND
	var zones := _crop(zones_of(kinds, w, h), w, Vector2i(pad, pad), size)
	var outer := size + Vector2i(border, border) * 2
	usec["shore"] = _lap(started)
	return {"kinds": _crop(kinds, w, Vector2i(MARGIN, MARGIN), outer), "river": _crop(river, w, Vector2i(MARGIN, MARGIN), outer),
		"zones": zones, "usec": usec}

## A parent's kinds as 0 or 1 per cell, one array per kind, for blending. A river cell counts as
## its sandy bank, so a child's river comes only from its smooth line, except where it meets other
## water, so the mouth stays joined. Keep it to refine many areas of one parent.
static func blend_shares(parent: Dictionary, parent_def: EcsSettlementDef) -> Array[PackedFloat32Array]:
	var pw := parent_def.size.x
	var ph := parent_def.size.y
	var parent_kinds := parent["kinds"] as PackedByteArray
	var parent_river := parent["river"] as PackedByteArray
	var blended := parent_kinds.duplicate()
	for i in pw * ph:
		if parent_river[i] == 0:
			continue
		blended[i] = SAND
		for side in SIDES:
			var x := i % pw + side.x
			var y := i / pw + side.y
			if x >= 0 and y >= 0 and x < pw and y < ph and parent_kinds[y * pw + x] == WATER and parent_river[y * pw + x] == 0:
				blended[i] = WATER
				break
	var shares: Array[PackedFloat32Array] = []
	for kind in KIND_COUNT:
		var share := PackedFloat32Array()
		share.resize(pw * ph)
		for i in pw * ph:
			share[i] = 1.0 if blended[i] == kind else 0.0
		shares.append(share)
	return shares

## Nodes for a child area of `def`'s size from its `zones`, seeded by `key` (a window or chunk),
## none on a cell `blocked` marks (a town's cleared ground).
static func refine_nodes(def: EcsSettlementDef, zones: PackedByteArray, rng_seed: int, key: Variant,
		entities: EcsEntityCatalog, blocked: PackedByteArray = PackedByteArray()) -> Array[Dictionary]:
	return _nodes(def, zones, entities, _rng(hash([rng_seed, key]), 7), blocked)

## The `size` window at `from` of a `w`-wide grid.
static func _crop(cells: PackedByteArray, w: int, from: Vector2i, size: Vector2i) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(size.x * size.y)
	for y in size.y:
		for x in size.x:
			out[y * size.x + x] = cells[(y + from.y) * w + x + from.x]
	return out

## Nodes and commands for finished `kinds`, their zones made here when `zones` is empty.
static func _finish(def: EcsSettlementDef, kinds: PackedByteArray, zones: PackedByteArray, rng: RandomNumberGenerator,
		catalog: EcsTownCatalog, entities: EcsEntityCatalog, usec: Dictionary) -> Dictionary:
	var w := def.size.x
	var h := def.size.y
	var started := Time.get_ticks_usec()
	if zones.is_empty():
		zones = zones_of(kinds, w, h)
	var placed := _nodes(def, zones, entities, rng)
	usec["nodes"] = _lap(started)
	started = Time.get_ticks_usec()
	var commands := terrain_commands(kinds, def.size, Vector2i.ZERO, catalog)
	var counts: Dictionary = {}
	for node: Dictionary in placed:
		commands.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, node["cell"], node["blueprint"], 0))
		counts[node["blueprint"]] = int(counts.get(node["blueprint"], 0)) + 1
	usec["commands"] = _lap(started)
	return {"commands": commands, "kinds": kinds, "zones": zones, "nodes": placed, "counts": counts, "usec": usec}

## SET_TERRAIN for every cell of `kinds` (`size`) that isn't grass, each moved by `offset`.
static func terrain_commands(kinds: PackedByteArray, size: Vector2i, offset: Vector2i, catalog: EcsTownCatalog) -> Array[EcsBuildCommand]:
	var commands: Array[EcsBuildCommand] = []
	for i in size.x * size.y:
		if kinds[i] != GRASS:
			commands.append(EcsBuildCommand.make(EcsBuildCommand.Kind.SET_TERRAIN, Vector2i(i % size.x, i / size.x) + offset,
				catalog.terrain_id(TERRAIN_KEYS[kinds[i]])))
	return commands

## `share` read between parent cell centres at `at` (parent cells, centre-based), edges clamped.
static func _blend(share: PackedFloat32Array, pw: int, ph: int, at: Vector2) -> float:
	var x0 := clampi(floori(at.x), 0, pw - 1)
	var y0 := clampi(floori(at.y), 0, ph - 1)
	var x1 := mini(x0 + 1, pw - 1)
	var y1 := mini(y0 + 1, ph - 1)
	var fx := clampf(at.x - floorf(at.x), 0.0, 1.0)
	var fy := clampf(at.y - floorf(at.y), 0.0, 1.0)
	var top := lerpf(share[y0 * pw + x0], share[y0 * pw + x1], fx)
	var bottom := lerpf(share[y1 * pw + x0], share[y1 * pw + x1], fx)
	return lerpf(top, bottom, fy)

## Paints a parent river's line into a child grid whose top-left child cell is `base`, scaled,
## its centre wandering a little by noise read in whole-map child cells.
static func _redraw(line: Dictionary, base: Vector2i, scale: int, kinds: PackedByteArray,
		river: PackedByteArray, w: int, h: int, jitter: FastNoiseLite) -> void:
	var points := line["points"] as PackedVector2Array
	var radii := line["radii"] as PackedFloat32Array
	var box := Rect2(-RIVER_JITTER, -RIVER_JITTER, w + RIVER_JITTER * 2.0, h + RIVER_JITTER * 2.0)
	for k in range(1, points.size()):
		var a := (points[k - 1] + Vector2(0.5, 0.5)) * scale - Vector2(0.5, 0.5) - Vector2(base)
		var b := (points[k] + Vector2(0.5, 0.5)) * scale - Vector2(0.5, 0.5) - Vector2(base)
		var radius := maxf(radii[k - 1], radii[k]) * scale + 1.0
		if not box.grow(radius).intersects(Rect2(a, Vector2.ZERO).expand(b)):
			continue
		var steps := maxi(ceili(a.distance_to(b)), 1)
		for s in steps:
			var at := a.lerp(b, float(s) / steps)
			var world := at + Vector2(base)
			var centre := at + Vector2(jitter.get_noise_2d(world.x, world.y), jitter.get_noise_2d(world.y, world.x)) * RIVER_JITTER
			_disc(kinds, river, w, h, Vector2i(roundi(centre.x), roundi(centre.y)), lerpf(radii[k - 1], radii[k], float(s) / steps) * scale)

## Per cell, a bit for each EcsNodeSpawnDef.Zone it is in.
static func zones_of(kinds: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var in_forest := distance_from(kinds, w, h, FOREST, true)
	var in_rock := distance_from(kinds, w, h, ROCK, true)
	var zones := PackedByteArray()
	zones.resize(w * h)
	for i in w * h:
		var bits := 0
		match kinds[i]:
			GRASS:
				bits = 1 << EcsNodeSpawnDef.Zone.MEADOW
			FOREST:
				bits = 1 << EcsNodeSpawnDef.Zone.FOREST
				if in_forest[i] <= EDGE_DEPTH:
					bits |= 1 << EcsNodeSpawnDef.Zone.FOREST_EDGE
				if in_forest[i] >= DEEP_DEPTH:
					bits |= 1 << EcsNodeSpawnDef.Zone.DEEP_FOREST
			ROCK:
				bits = 1 << EcsNodeSpawnDef.Zone.ROCK
				if in_rock[i] >= 2:
					bits |= 1 << EcsNodeSpawnDef.Zone.ROCK_INNER
			SAND:
				bits = 1 << EcsNodeSpawnDef.Zone.SHORE
			WATER:
				var x := i % w
				var y := i / w
				for side in SIDES:
					var nx := x + side.x
					var ny := y + side.y
					if nx >= 0 and ny >= 0 and nx < w and ny < h and kinds[ny * w + nx] != WATER:
						bits = 1 << EcsNodeSpawnDef.Zone.SHALLOW
						break
		zones[i] = bits
	return zones

## For every cell, its 4-connected step distance to the nearest cell that is (`inside` false) or
## is not (`inside` true) of `kind`; 0 on those cells themselves, 255 past 254.
static func distance_from(kinds: PackedByteArray, w: int, h: int, kind: int, inside: bool) -> PackedByteArray:
	var dist := PackedByteArray()
	dist.resize(w * h)
	dist.fill(255)
	var queue := PackedInt32Array()
	for i in w * h:
		if (kinds[i] == kind) != inside:
			dist[i] = 0
			queue.append(i)
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var next := dist[i] + 1
		if next >= 255:
			continue
		var x := i % w
		var y := i / w
		if x > 0 and dist[i - 1] > next:
			dist[i - 1] = next
			queue.append(i - 1)
		if x < w - 1 and dist[i + 1] > next:
			dist[i + 1] = next
			queue.append(i + 1)
		if y > 0 and dist[i - w] > next:
			dist[i - w] = next
			queue.append(i - w)
		if y < h - 1 and dist[i + w] > next:
			dist[i + w] = next
			queue.append(i + w)
	return dist

## Labels the 4-connected areas of cells where `member[i]` is non-zero: a label per cell (0 = not
## a member), and each label's size at its index in the second array.
static func areas(member: PackedByteArray, w: int, h: int) -> Array:
	var label := PackedInt32Array()
	label.resize(w * h)
	var sizes := PackedInt32Array([0])
	var queue := PackedInt32Array()
	for start in w * h:
		if member[start] == 0 or label[start] != 0:
			continue
		var id := sizes.size()
		var size := 0
		queue.clear()
		queue.append(start)
		label[start] = id
		var head := 0
		while head < queue.size():
			var i := queue[head]
			head += 1
			size += 1
			var x := i % w
			var y := i / w
			for side in SIDES:
				var nx := x + side.x
				var ny := y + side.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var n := ny * w + nx
				if member[n] != 0 and label[n] == 0:
					label[n] = id
					queue.append(n)
		sizes.append(size)
	return [label, sizes]

static func _lake(def: EcsSettlementDef, kinds: PackedByteArray, rng: RandomNumberGenerator) -> void:
	var w := def.size.x
	var h := def.size.y
	var noise := _noise(rng, 3.0 / maxf(w, h))
	var values := noise.get_image(w, h).get_data()
	var centre := Vector2(rng.randf_range(w * 0.3, w * 0.7), rng.randf_range(h * 0.3, h * 0.7))
	var reach := minf(w, h) * 0.5
	var score := PackedFloat32Array()
	score.resize(w * h)
	for i in w * h:
		var falloff := 1.0 - Vector2(i % w, i / w).distance_to(centre) / reach
		score[i] = falloff * 0.7 + values[i] / 255.0 * 0.3
	var cut := _cut_for(score, def.water_share)
	var water := PackedByteArray()
	water.resize(w * h)
	for i in w * h:
		water[i] = 1 if score[i] >= cut else 0
	var found := areas(water, w, h)
	var biggest := _largest(found[1])
	for i in w * h:
		if (found[0] as PackedInt32Array)[i] == biggest:
			kinds[i] = WATER

## A river from one edge to the opposite one, along x when `along_x`; its line, in cells.
static func _river(def: EcsSettlementDef, kinds: PackedByteArray, river: PackedByteArray, rng: RandomNumberGenerator,
		along_x: bool) -> Dictionary:
	var w := def.size.x
	var h := def.size.y
	var length := w if along_x else h
	var span := h if along_x else w
	var from := rng.randf_range(span * 0.25, span * 0.75)
	var to := rng.randf_range(span * 0.25, span * 0.75)
	var bends := _noise(rng, 2.0 / length)
	var widths := _noise(rng, 0.03)
	var points := PackedVector2Array()
	var radii := PackedFloat32Array()
	for t in length:
		var centre := lerpf(from, to, float(t) / (length - 1)) + bends.get_noise_1d(t) * span * 0.3
		var radius := lerpf(def.river_width.x, def.river_width.y, (widths.get_noise_1d(t) + 1.0) * 0.5) * 0.5
		var here := clampf(centre, ceilf(radius), span - 1 - ceilf(radius))
		points.append(Vector2(t, here) if along_x else Vector2(here, t))
		radii.append(radius)
	# Discs every half cell along each segment: the same course a refine redraws, scaled.
	for k in range(1, length):
		var steps := maxi(ceili(points[k - 1].distance_to(points[k]) * 2.0), 1)
		for s in steps + 1:
			var at := points[k - 1].lerp(points[k], float(s) / steps)
			_disc(kinds, river, w, h, Vector2i(roundi(at.x), roundi(at.y)), lerpf(radii[k - 1], radii[k], float(s) / steps))
	return {"points": points, "radii": radii}

## Paints water in a disc of `radius` round `at`; land it turns to water is marked in `river`.
static func _disc(kinds: PackedByteArray, river: PackedByteArray, w: int, h: int, at: Vector2i, radius: float) -> void:
	var r := ceili(radius)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var x := at.x + dx
			var y := at.y + dy
			if dx * dx + dy * dy <= radius * radius and x >= 0 and y >= 0 and x < w and y < h:
				var i := y * w + x
				if kinds[i] != WATER:
					kinds[i] = WATER
					river[i] = 1

## Sea along one random side; returns that side.
static func _coast(def: EcsSettlementDef, kinds: PackedByteArray, rng: RandomNumberGenerator) -> Vector2i:
	var w := def.size.x
	var h := def.size.y
	var side := SIDES[rng.randi_range(0, 3)]
	var vertical := side.x != 0
	var deep := (w if vertical else h) * def.water_share
	var noise := _noise(rng, 0.02)
	for i in w * h:
		var x := i % w
		var y := i / w
		var along := y if vertical else x
		var out := x if side == Vector2i.LEFT else (w - 1 - x if side == Vector2i.RIGHT else (y if side == Vector2i.UP else h - 1 - y))
		if out < deep * (1.0 + noise.get_noise_1d(along) * 0.6):
			kinds[i] = WATER
	return side

static func _rock(def: EcsSettlementDef, kinds: PackedByteArray, from_water: PackedByteArray, rng: RandomNumberGenerator) -> void:
	var w := def.size.x
	var h := def.size.y
	var values := _noise(rng, 5.0 / maxf(w, h)).get_image(w, h).get_data()
	var score := PackedFloat32Array()
	score.resize(w * h)
	for i in w * h:
		score[i] = values[i] if kinds[i] == GRASS and from_water[i] > def.shore_width + 2 else -1.0
	var cut := _cut_for(score, def.rock_share)
	var rock := PackedByteArray()
	rock.resize(w * h)
	for i in w * h:
		rock[i] = 1 if score[i] >= 0.0 and score[i] >= cut else 0
	var found := areas(rock, w, h)
	var label := found[0] as PackedInt32Array
	var sizes := found[1] as PackedInt32Array
	for i in w * h:
		if label[i] != 0 and sizes[label[i]] >= MIN_ROCK_BLOB:
			kinds[i] = ROCK

static func _forest(def: EcsSettlementDef, kinds: PackedByteArray, rng: RandomNumberGenerator) -> void:
	var w := def.size.x
	var h := def.size.y
	var values := _noise(rng, 6.0 / maxf(w, h)).get_image(w, h).get_data()
	var score := PackedFloat32Array()
	score.resize(w * h)
	for i in w * h:
		score[i] = values[i] if kinds[i] == GRASS else -1.0
	var cut := _cut_for(score, def.forest_share)
	for i in w * h:
		if score[i] >= 0.0 and score[i] >= cut:
			kinds[i] = FOREST

static func _nodes(def: EcsSettlementDef, zones: PackedByteArray, entities: EcsEntityCatalog,
		rng: RandomNumberGenerator, blocked: PackedByteArray = PackedByteArray()) -> Array[Dictionary]:
	var w := def.size.x
	var h := def.size.y
	var lists: Array[PackedInt32Array] = []
	for zone in EcsNodeSpawnDef.Zone.size():
		lists.append(PackedInt32Array())
	for i in w * h:
		for zone in EcsNodeSpawnDef.Zone.size():
			if zones[i] & (1 << zone):
				lists[zone].append(i)
	# 0 free, 1 kept clear, 2 a node.
	var taken := PackedByteArray()
	taken.resize(w * h)
	if not blocked.is_empty():
		taken = blocked.duplicate()
	var placed: Array[Dictionary] = []
	for spawn in def.nodes:
		var place := EcsBuildRules.template(entities, spawn.blueprint, &"grid_position") as EcsGridPositionComponent
		var size := place.size if place != null else Vector2i.ONE
		var bit := 1 << spawn.zone
		var cells := lists[spawn.zone]
		var count := 0
		for start in cells:
			if rng.randf() < spawn.density:
				count += _clump(spawn, start, size, bit, zones, taken, w, h, rng, placed)
		# Too few by chance: more clumps at random cells of the zone, while it has room.
		var tries := 0
		while count < spawn.min_count and tries < 200 and not cells.is_empty():
			tries += 1
			count += _clump(spawn, cells[rng.randi_range(0, cells.size() - 1)], size, bit, zones, taken, w, h, rng, placed)
	return placed

## One clump of `spawn` grown by random walk from cell `start`; how many nodes it placed.
static func _clump(spawn: EcsNodeSpawnDef, start: int, size: Vector2i, bit: int, zones: PackedByteArray,
		taken: PackedByteArray, w: int, h: int, rng: RandomNumberGenerator, placed: Array[Dictionary]) -> int:
	var at := Vector2i(start % w, start / w)
	var made := 0
	for k in spawn.cluster:
		if _fits(at, size, bit, zones, taken, w, h):
			_take(at, size, spawn.keep_clear, taken, w, h)
			placed.append({"blueprint": spawn.blueprint, "cell": at, "size": size})
			made += 1
		at += SIDES[rng.randi_range(0, 3)]
	return made

static func _fits(at: Vector2i, size: Vector2i, bit: int, zones: PackedByteArray, taken: PackedByteArray, w: int, h: int) -> bool:
	for dy in size.y:
		for dx in size.x:
			var x := at.x + dx
			var y := at.y + dy
			if x < 0 or y < 0 or x >= w or y >= h:
				return false
			var i := y * w + x
			if taken[i] != 0 or not (zones[i] & bit):
				return false
	return true

static func _take(at: Vector2i, size: Vector2i, clear: int, taken: PackedByteArray, w: int, h: int) -> void:
	for dy in range(-clear, size.y + clear):
		for dx in range(-clear, size.x + clear):
			var x := at.x + dx
			var y := at.y + dy
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			var inside := dx >= 0 and dy >= 0 and dx < size.x and dy < size.y
			var i := y * w + x
			if inside:
				taken[i] = 2
			elif taken[i] == 0:
				taken[i] = 1

## The score at which the top `share` of the scored cells (score >= 0) begins.
static func _cut_for(score: PackedFloat32Array, share: float) -> float:
	var sorted := score.duplicate()
	sorted.sort()
	var want := int(score.size() * share)
	if want <= 0:
		return INF
	return sorted[maxi(sorted.size() - want, 0)]

static func _largest(sizes: PackedInt32Array) -> int:
	var best := 0
	for id in range(1, sizes.size()):
		if best == 0 or sizes[id] > sizes[best]:
			best = id
	return best

static func _noise(rng: RandomNumberGenerator, frequency: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_octaves = 3
	return noise

static func _rng(rng_seed: int, stage: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([rng_seed, stage])
	return rng

static func _lap(started: int) -> int:
	return Time.get_ticks_usec() - started
