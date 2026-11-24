class_name WorldMap
extends RefCounted

## L3, the world map, made whole from a seed and read-only after (safe for workers). Per cell: height (Perlin),
## heat (latitude bent by a slow noise, colder up high) and humidity (a broad Perlin, wetter by the sea, drier
## inland, wetter by rivers and lakes); both smoothed. Water is
## drained over the whole map: Priority-Flood fills basins into lakes and gives every land cell the cell it
## drains to, flow adds up the rain downstream, and cells with enough flow are rivers, traced as lines from
## their heads to the sea, a lake or a bigger river. Biomes come from heat and humidity, sea, mountains and
## snow from height. Drawn by art/l3_map.gdshader from `fields_image()` and the river lines.

const SIZE := Vector2i(256, 128)
## Height (0..1) of the sea, and where mountains and snow begin.
const SEA: float = 0.5
const MOUNTAIN: float = 0.74
const SNOW: float = 0.84
## A land cell this much below its filled level is lake.
const LAKE_DEPTH: float = 0.02
## Lakes smaller than this, in cells, are dropped: too small to show at L3.
const LAKE_CELLS: int = 4
## Flow, in cells of rain, that makes a river; no rivers where it is this cold (frozen).
const RIVER_FLOW: float = 16.0
const RIVER_HEAT: float = 0.14
## Distance from the sea, in cells, at which land is as dry as inland gets.
const INLAND: float = 18.0
## Humidity added next to a river or lake.
const WETTER: float = 0.15
## Side of the biome lookup, heat across, humidity down.
const TABLE: int = 32
const NEIGHBOURS: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0),
	Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]

## The land biomes by heat and humidity: name and map colour.
const BIOMES: Array[Array] = [
	["Ice cap", Color8(236, 240, 246)], ["Tundra", Color8(150, 158, 128)], ["Wet tundra", Color8(124, 140, 116)],
	["Cold steppe", Color8(138, 150, 96)], ["Taiga", Color8(66, 104, 72)], ["Dry grassland", Color8(170, 164, 104)],
	["Grassland", Color8(110, 150, 74)], ["Temperate forest", Color8(70, 122, 60)], ["Desert", Color8(214, 186, 122)],
	["Savanna", Color8(170, 168, 86)], ["Tropical forest", Color8(40, 104, 52)]]
## What height and water decide: name and map colour.
const WATERS: Array[Array] = [["Deep sea", Color8(42, 86, 134)], ["Shallow sea", Color8(70, 124, 168)],
	["Sea ice", Color8(214, 226, 238)], ["Lake", Color8(70, 124, 168)], ["River", Color8(70, 124, 168)],
	["Mountains", Color8(128, 122, 112)], ["Snow peaks", Color8(240, 242, 246)]]
## The map modes besides biomes: name, which field (0 height, 1 heat, 2 humidity) and its bands as
## [from, colour, name]. Heat's bands are the biome table's heat steps.
const MODES: Array[Dictionary] = [
	{"name": "Heat", "field": 1, "bands": [[0.0, Color8(52, 74, 128), "Frozen"], [0.14, Color8(96, 138, 178), "Cold"],
		[0.28, Color8(150, 176, 170), "Cool"], [0.44, Color8(206, 196, 140), "Mild"], [0.64, Color8(214, 148, 84), "Warm"],
		[0.8, Color8(170, 66, 46), "Hot"]]},
	{"name": "Height", "field": 0, "bands": [[0.0, Color8(30, 58, 96), "Deep sea"], [0.42, Color8(62, 110, 152), "Sea"],
		[0.5, Color8(104, 140, 80), "Lowland"], [0.6, Color8(150, 146, 90), "Upland"], [0.74, Color8(128, 112, 96), "Mountain"],
		[0.84, Color8(238, 236, 230), "Peak"]]},
	{"name": "Humidity", "field": 2, "bands": [[0.0, Color8(204, 164, 98), "Arid"], [0.3, Color8(190, 180, 112), "Dry"],
		[0.45, Color8(130, 160, 92), "Moderate"], [0.55, Color8(78, 140, 110), "Wet"], [0.7, Color8(44, 100, 120), "Soaked"]]}]

var height := PackedFloat32Array()
var heat := PackedFloat32Array()
var humidity := PackedFloat32Array()
## The height water stands at once basins are filled; above `height` in a lake.
var filled := PackedFloat32Array()
var lake := PackedByteArray()
## The cell each land cell drains to; -1 for sea and the map's edge, where water leaves.
var down := PackedInt32Array()
## Rain gathered from every cell upstream, itself included.
var flow := PackedFloat32Array()
var river := PackedByteArray()
## Each river: {"points": cell positions (PackedVector2Array), "flows": flow at each (PackedFloat32Array)}.
var rivers: Array[Dictionary] = []
var make_usec: int = 0

var _heap_keys := PackedFloat32Array()
var _heap_cells := PackedInt32Array()

## The world for `salt`. A non-empty `progress` gets its first item set from 0 to 1 as stages finish, for a
## loading bar on another thread.
static func make(salt: int, progress: Array = []) -> WorldMap:
	var started := Time.get_ticks_usec()
	var map := WorldMap.new()
	var stages: Array[Callable] = [map._fields.bind(salt), map._drain, map._wet, map._trace.bind(salt)]
	# Progress after each stage, by how long each takes (measured).
	var done: Array[float] = [0.62, 0.98, 0.99, 1.0]
	for k in stages.size():
		stages[k].call()
		if not progress.is_empty():
			progress[0] = done[k]
	map.make_usec = Time.get_ticks_usec() - started
	return map

static func index(cell: Vector2i) -> int:
	return cell.y * SIZE.x + cell.x

static func has(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < SIZE.x and cell.y < SIZE.y

## Noise for `salt`, sampled on a cylinder by `_at`, so it has no seam east-west.
static func noise(salt: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = salt
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 5
	n.frequency = 0.035
	return n

## `n` at cell `p`: x goes round a cylinder of the map's width, y along it; about -1..1.
static func _at(n: FastNoiseLite, p: Vector2) -> float:
	var angle := p.x / SIZE.x * TAU
	var radius := SIZE.x / TAU
	return n.get_noise_3d(cos(angle) * radius, sin(angle) * radius, p.y)

func _fields(salt: int) -> void:
	var land := noise(salt)
	var warp := noise(salt + 1)
	warp.frequency = 0.015
	warp.fractal_octaves = 2
	var wet := noise(salt + 2)
	wet.frequency = 0.015
	wet.fractal_octaves = 3
	var n := SIZE.x * SIZE.y
	height.resize(n)
	heat.resize(n)
	humidity.resize(n)
	for y in SIZE.y:
		for x in SIZE.x:
			var p := Vector2(x + 0.5, y + 0.5)
			height[y * SIZE.x + x] = clampf(0.5 + _at(land, p) * 1.15, 0.0, 1.0)
	var inland := _sea_distance()
	for y in SIZE.y:
		for x in SIZE.x:
			var p := Vector2(x + 0.5, y + 0.5)
			var i := y * SIZE.x + x
			var lat := absf(p.y - SIZE.y * 0.5) / (SIZE.y * 0.5)
			heat[i] = clampf(1.0 - lat + _at(warp, p) * 0.4 - maxf(height[i] - SEA, 0.0) * 0.9, 0.0, 1.0)
			# Wetter by the sea, drier deep inland.
			humidity[i] = clampf(0.62 + _at(wet, p) * 1.0 - minf(inland[i] / INLAND, 1.0) * 0.35, 0.0, 1.0)
	_blur(heat, 2)
	_blur(humidity, 2)

## Each cell's distance, in cells, to the nearest sea (0 at sea).
func _sea_distance() -> PackedFloat32Array:
	var distance := PackedFloat32Array()
	distance.resize(SIZE.x * SIZE.y)
	distance.fill(INF)
	var queue := PackedInt32Array()
	for i in distance.size():
		if height[i] < SEA:
			distance[i] = 0.0
			queue.append(i)
	var k := 0
	while k < queue.size():
		var c := queue[k]
		k += 1
		var at := Vector2i(c % SIZE.x, c / SIZE.x)
		for step in NEIGHBOURS:
			if has(at + step):
				var j := index(at + step)
				if distance[j] == INF:
					distance[j] = distance[c] + 1.0
					queue.append(j)
	return distance

## Averages each cell with its neighbours, `passes` times, so fields have no specks.
static func _blur(field: PackedFloat32Array, passes: int) -> void:
	for pass_ in passes:
		var copy := field.duplicate()
		for y in SIZE.y:
			for x in SIZE.x:
				var sum := 0.0
				var count := 0
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var at := Vector2i(x + dx, y + dy)
						if has(at):
							sum += copy[index(at)]
							count += 1
				field[y * SIZE.x + x] = sum / count

## Priority-Flood (with a small rise on flats so every cell drains): from the sea and the map's edge inward,
## lowest first, each cell reached stands at least a little above the cell it was reached from. Then every
## land cell drains to its lowest neighbour on that filled surface (always lower, so water never circles), and
## rain is added up from the last cell filled back to the first.
func _drain() -> void:
	var n := SIZE.x * SIZE.y
	filled = height.duplicate()
	down.resize(n)
	down.fill(-1)
	flow.resize(n)
	lake.resize(n)
	lake.fill(0)
	var closed := PackedByteArray()
	closed.resize(n)
	var order := PackedInt32Array()
	for y in SIZE.y:
		for x in SIZE.x:
			var i := y * SIZE.x + x
			if height[i] < SEA or x == 0 or y == 0 or x == SIZE.x - 1 or y == SIZE.y - 1:
				closed[i] = 1
				_push(filled[i], i)
	while not _heap_cells.is_empty():
		var c := _pop()
		order.append(c)
		var at := Vector2i(c % SIZE.x, c / SIZE.x)
		for step in NEIGHBOURS:
			var next := at + step
			if not has(next):
				continue
			var j := index(next)
			if closed[j] == 1:
				continue
			closed[j] = 1
			filled[j] = maxf(height[j], filled[c] + 0.00001)
			_push(filled[j], j)
	for y in range(1, SIZE.y - 1):
		for x in range(1, SIZE.x - 1):
			var i := y * SIZE.x + x
			if height[i] < SEA:
				continue
			var low := filled[i]
			for step in NEIGHBOURS:
				var j := index(Vector2i(x, y) + step)
				if filled[j] < low:
					low = filled[j]
					down[i] = j
	for i in n:
		flow[i] = 0.2 + humidity[i] if height[i] >= SEA else 0.0
		if height[i] >= SEA and filled[i] - height[i] > LAKE_DEPTH:
			lake[i] = 1
	_drop_small_lakes()
	for k in range(order.size() - 1, -1, -1):
		var i := order[k]
		if down[i] >= 0:
			flow[down[i]] += flow[i]

## Clears every lake of fewer than LAKE_CELLS cells.
func _drop_small_lakes() -> void:
	var seen := PackedByteArray()
	seen.resize(lake.size())
	for start in lake.size():
		if lake[start] == 0 or seen[start] == 1:
			continue
		var cells := PackedInt32Array([start])
		seen[start] = 1
		var k := 0
		while k < cells.size():
			var at := Vector2i(cells[k] % SIZE.x, cells[k] / SIZE.x)
			k += 1
			for step in NEIGHBOURS:
				if has(at + step):
					var j := index(at + step)
					if lake[j] == 1 and seen[j] == 0:
						seen[j] = 1
						cells.append(j)
		if cells.size() < LAKE_CELLS:
			for c in cells:
				lake[c] = 0

## Land beside a river or lake gets wetter.
func _wet() -> void:
	river.resize(SIZE.x * SIZE.y)
	river.fill(0)
	for i in river.size():
		if height[i] >= SEA and lake[i] == 0 and flow[i] >= RIVER_FLOW and heat[i] >= RIVER_HEAT:
			river[i] = 1
	var add := PackedFloat32Array()
	add.resize(river.size())
	for i in river.size():
		if river[i] == 0 and lake[i] == 0:
			continue
		var at := Vector2i(i % SIZE.x, i / SIZE.x)
		add[i] = WETTER
		for step in NEIGHBOURS:
			if has(at + step):
				add[index(at + step)] = WETTER
	for i in add.size():
		humidity[i] = minf(humidity[i] + add[i], 1.0)

## Each river as a line: from a head (a river cell no river flows into) down to the sea, a lake or where it
## joins another, through cell middles nudged a little by noise and smoothed.
func _trace(salt: int) -> void:
	var fed := PackedByteArray()
	fed.resize(river.size())
	for i in river.size():
		if river[i] == 1 and down[i] >= 0:
			fed[down[i]] = 1
	var walked := PackedByteArray()
	walked.resize(river.size())
	for i in river.size():
		if river[i] == 0 or fed[i] == 1:
			continue
		var points := PackedVector2Array()
		var flows := PackedFloat32Array()
		var c := i
		while true:
			points.append(_wobble(c, salt))
			flows.append(flow[c])
			if c < 0 or river[c] == 0 or walked[c] == 1:
				break
			walked[c] = 1
			var next := down[c]
			if next < 0:
				break
			c = next
		if points.size() >= 3:
			rivers.append({"points": _smooth(points), "flows": _smooth_flows(flows)})

## Cell `i`'s middle, nudged up to a quarter cell by its hash, so rivers wander.
static func _wobble(i: int, salt: int) -> Vector2:
	var h := (i * 2654435761 + salt * 40503) & 0xffffffff
	var dx := float(h & 0xffff) / 65535.0 - 0.5
	var dy := float((h >> 16) & 0xffff) / 65535.0 - 0.5
	return Vector2(i % SIZE.x + 0.5 + dx * 0.5, i / SIZE.x + 0.5 + dy * 0.5)

## Chaikin's corner cutting, twice; the ends stay.
static func _smooth(points: PackedVector2Array) -> PackedVector2Array:
	var out := points
	for pass_ in 2:
		var next := PackedVector2Array([out[0]])
		for k in out.size() - 1:
			next.append(out[k].lerp(out[k + 1], 0.25))
			next.append(out[k].lerp(out[k + 1], 0.75))
		next.append(out[out.size() - 1])
		out = next
	return out

## The flows to go with `_smooth`'s points.
static func _smooth_flows(flows: PackedFloat32Array) -> PackedFloat32Array:
	var out := flows
	for pass_ in 2:
		var next := PackedFloat32Array([out[0]])
		for k in out.size() - 1:
			next.append(lerpf(out[k], out[k + 1], 0.25))
			next.append(lerpf(out[k], out[k + 1], 0.75))
		next.append(out[out.size() - 1])
		out = next
	return out

func _push(key: float, cell: int) -> void:
	_heap_keys.append(key)
	_heap_cells.append(cell)
	var k := _heap_keys.size() - 1
	while k > 0:
		var parent := (k - 1) >> 1
		if _heap_keys[parent] <= _heap_keys[k]:
			break
		_swap(k, parent)
		k = parent

func _pop() -> int:
	var top := _heap_cells[0]
	var last := _heap_keys.size() - 1
	_swap(0, last)
	_heap_keys.resize(last)
	_heap_cells.resize(last)
	var k := 0
	while true:
		var a := k * 2 + 1
		var b := a + 1
		var least := k
		if a < last and _heap_keys[a] < _heap_keys[least]:
			least = a
		if b < last and _heap_keys[b] < _heap_keys[least]:
			least = b
		if least == k:
			break
		_swap(k, least)
		k = least
	return top

func _swap(a: int, b: int) -> void:
	var key := _heap_keys[a]
	_heap_keys[a] = _heap_keys[b]
	_heap_keys[b] = key
	var cell := _heap_cells[a]
	_heap_cells[a] = _heap_cells[b]
	_heap_cells[b] = cell

## A river's width, in cells, at flow `amount`.
static func river_width(amount: float) -> float:
	return clampf(0.22 + 0.1 * log(amount / RIVER_FLOW) / log(2.0), 0.22, 0.8)

## The fields the map shader reads, a pixel a cell: R height, G heat, B humidity, A lake.
func fields_image() -> Image:
	var image := Image.create_empty(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	for y in SIZE.y:
		for x in SIZE.x:
			var i := y * SIZE.x + x
			image.set_pixel(x, y, Color(height[i], heat[i], humidity[i], float(lake[i])))
	return image

## The land biome (index into BIOMES) at heat `t` and humidity `m`, both 0..1.
static func biome_at(t: float, m: float) -> int:
	if t < 0.14:
		return 0
	if t < 0.28:
		return 1 if m < 0.5 else 2
	if t < 0.44:
		return 3 if m < 0.38 else 4
	if t < 0.64:
		if m < 0.3:
			return 5
		return 6 if m < 0.55 else 7
	if m < 0.3:
		return 8
	return 9 if m < 0.55 else 10

## The biome lookup the map shader reads: heat across, humidity down.
static func table() -> Image:
	var image := Image.create_empty(TABLE, TABLE, false, Image.FORMAT_RGB8)
	for y in TABLE:
		for x in TABLE:
			image.set_pixel(x, y, BIOMES[biome_at((x + 0.5) / TABLE, (y + 0.5) / TABLE)][1])
	return image

## A mode's bands as a strip the map shader reads, hard steps between them.
static func ramp(mode: Dictionary) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var offsets := PackedFloat32Array()
	var colours := PackedColorArray()
	for band: Array in mode["bands"]:
		offsets.append(band[0])
		colours.append(band[1])
	gradient.offsets = offsets
	gradient.colors = colours
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	texture.width = 512
	return texture

## Cell `cell`'s colour, as the map shader draws its middle.
func colour(cell: Vector2i) -> Color:
	return kind(cell)[1]

## What `cell` is, as [name, colour] from WATERS or BIOMES (rivers aside).
func kind(cell: Vector2i) -> Array:
	var i := index(Vector2i(clampi(cell.x, 0, SIZE.x - 1), clampi(cell.y, 0, SIZE.y - 1)))
	if height[i] < SEA:
		if heat[i] < 0.12:
			return WATERS[2]
		return WATERS[0] if height[i] < SEA - 0.05 else WATERS[1]
	if lake[i] == 1:
		return WATERS[3]
	if height[i] > SNOW:
		return WATERS[6]
	if height[i] > MOUNTAIN:
		return WATERS[5]
	return BIOMES[biome_at(heat[i], humidity[i])]

## The name of the band of map mode `mode` that `value` falls in.
static func band(mode: int, value: float) -> String:
	var name := ""
	for b: Array in MODES[mode]["bands"]:
		if value >= b[0]:
			name = b[2]
	return name
