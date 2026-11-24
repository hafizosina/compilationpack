extends Node2D

## Headless test for module 13's world view data: the L3 world map (same seed same world, poles cold, water
## drains to the sea or a lake, rivers end in water, ice or another river, lakes big enough) and the chunk store, and
## that a placeholder chunk shows its parent cell.
##
##   "$GODOT" --headless --path . "res://13. World Generator/tests/world_test.tscn"
##
## Exits 0 only if every check passes. Prints the world's make time and its water.

const SEEDS: Array[int] = [0, 1, 2]

var _checks: int = 0
var _failures: int = 0

func _ready() -> void:
	var maps: Array[WorldMap] = []
	for salt in SEEDS:
		maps.append(WorldMap.make(salt))
	_the_same_seed_gives_the_same_world(maps[0])
	for k in SEEDS.size():
		var map := maps[k]
		var lakes := 0
		for i in map.lake.size():
			lakes += map.lake[i]
		print("[world] seed %d: made in %.0f ms, %d rivers, %d lake cells" % [SEEDS[k], map.make_usec / 1000.0, map.rivers.size(), lakes])
		_poles_are_cold_and_the_middle_warm(SEEDS[k], map)
		_every_land_cell_drains_away(SEEDS[k], map)
		_rivers_end_in_water_or_another_river(SEEDS[k], map)
		_lakes_are_big_enough(SEEDS[k], map)
	_check("seeds give different worlds", maps[0].height != maps[1].height)
	_chunks_are_found_nearest_first_and_trimmed()
	_a_chunk_shows_its_parent(maps[0])
	print("[world] %d/%d checks passed" % [_checks - _failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)

func _the_same_seed_gives_the_same_world(map: WorldMap) -> void:
	var again := WorldMap.make(SEEDS[0])
	_check("the same seed gives the same world", again.height == map.height and again.humidity == map.humidity
		and again.lake == map.lake and again.rivers.size() == map.rivers.size())

func _poles_are_cold_and_the_middle_warm(salt: int, map: WorldMap) -> void:
	var rows := func(from: int, to: int) -> float:
		var sum := 0.0
		for y in range(from, to):
			for x in WorldMap.SIZE.x:
				sum += map.heat[y * WorldMap.SIZE.x + x]
		return sum / ((to - from) * WorldMap.SIZE.x)
	var north: float = rows.call(0, 6)
	var south: float = rows.call(WorldMap.SIZE.y - 6, WorldMap.SIZE.y)
	var middle: float = rows.call(WorldMap.SIZE.y / 2 - 3, WorldMap.SIZE.y / 2 + 3)
	_check("seed %d: poles frozen (%.2f, %.2f), middle warm (%.2f)" % [salt, north, south, middle],
		north < 0.14 and south < 0.14 and middle > 0.6)

## Every land cell's water reaches the sea or the map's edge, each step to a lower filled cell.
func _every_land_cell_drains_away(salt: int, map: WorldMap) -> void:
	var bad := 0
	for i in map.height.size():
		if map.height[i] < WorldMap.SEA:
			continue
		var c := i
		var steps := 0
		while map.down[c] >= 0 and steps < 100000:
			if map.filled[map.down[c]] >= map.filled[c]:
				bad += 1
				break
			c = map.down[c]
			steps += 1
		var at := Vector2i(c % WorldMap.SIZE.x, c / WorldMap.SIZE.x)
		var edge := at.x == 0 or at.y == 0 or at.x == WorldMap.SIZE.x - 1 or at.y == WorldMap.SIZE.y - 1
		if map.height[c] >= WorldMap.SEA and not edge:
			bad += 1
	_check("seed %d: every land cell drains downhill to the sea or the edge (%d wrong)" % [salt, bad], bad == 0)

func _rivers_end_in_water_or_another_river(salt: int, map: WorldMap) -> void:
	var bad := 0
	for river: Dictionary in map.rivers:
		var points: PackedVector2Array = river["points"]
		var end := Vector2i(points[points.size() - 1].floor())
		var i := WorldMap.index(end)
		var edge := end.x == 0 or end.y == 0 or end.x == WorldMap.SIZE.x - 1 or end.y == WorldMap.SIZE.y - 1
		var frozen := map.heat[i] < WorldMap.RIVER_HEAT
		if not (map.height[i] < WorldMap.SEA or map.lake[i] == 1 or map.river[i] == 1 or frozen or edge):
			bad += 1
	_check("seed %d: %d rivers each end in the sea, a lake, a river, ice or the edge (%d wrong)" % [salt, map.rivers.size(), bad],
		bad == 0 and map.rivers.size() > 20)

func _lakes_are_big_enough(salt: int, map: WorldMap) -> void:
	var small := 0
	var seen := PackedByteArray()
	seen.resize(map.lake.size())
	for start in map.lake.size():
		if map.lake[start] == 0 or seen[start] == 1:
			continue
		var cells := [start]
		seen[start] = 1
		var k := 0
		while k < cells.size():
			var at := Vector2i(cells[k] % WorldMap.SIZE.x, cells[k] / WorldMap.SIZE.x)
			k += 1
			for step in WorldMap.NEIGHBOURS:
				if WorldMap.has(at + step):
					var j := WorldMap.index(at + step)
					if map.lake[j] == 1 and seen[j] == 0:
						seen[j] = 1
						cells.append(j)
		if cells.size() < WorldMap.LAKE_CELLS:
			small += 1
	_check("seed %d: no lake under %d cells (%d)" % [salt, WorldMap.LAKE_CELLS, small], small == 0)

func _chunks_are_found_nearest_first_and_trimmed() -> void:
	var store := WorldChunkStore.new(32, Vector2i(320, 320), 4)
	var around := store.around(Rect2i(64, 64, 64, 64), 1)
	_check("a view of 2x2 chunks with a ring of 1 asks for 4x4, nearest first",
		around.size() == 16 and around[0] in [Vector2i(2, 2), Vector2i(2, 3), Vector2i(3, 2), Vector2i(3, 3)])
	_check("chunks wrap east-west", store.wrapped(Vector2i(-1, 3)) == Vector2i(9, 3))
	for k in 6:
		store.put(Vector2i(k, 0), {}, 0)
	store.trim()
	_check("plans past the cap are dropped, oldest first", store.plans.size() == 4 and not store.plans.has(Vector2i(0, 0)))

func _a_chunk_shows_its_parent(map: WorldMap) -> void:
	var cell := Vector2i(100, 60)
	var image := WorldPlaceholder.chunk_image(1, Vector2i(cell.x * 2, cell.y * 2), 64, map)
	var shown := image.get_pixel(20, 21)
	var close := func(c: Color) -> bool: return absf(shown.r - c.r) + absf(shown.g - c.g) + absf(shown.b - c.b) < 0.02
	_check("an L2 chunk shows its L3 cell's colour", close.call(map.colour(cell)) or close.call(map.colour(cell).darkened(0.06)))

func _check(what: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
	print("[world] %s  %s" % ["ok  " if passed else "FAIL", what])
