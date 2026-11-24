class_name WorldPlaceholder
extends RefCounted

## Step 1's stand-in content, pure and worker-safe: an L3 map of fields (height, temperature, moisture) drawn
## by art/l3_map.gdshader, and L2 and L1 chunks that show their parent cell's colour with a checker, so
## streaming and levels can be seen before real world gen. L2 and L1 colours come from the L3 colours.

## L3's size in cells; east-west wraps.
const L3 := Vector2i(256, 128)
## Child cells per parent cell side.
const SPLIT: int = 128
## Height (0..1) of the sea, and where mountains and snow begin.
const SEA: float = 0.5
const MOUNTAIN: float = 0.74
const SNOW: float = 0.84
## Side of the biome lookup, temperature across, moisture down.
const TABLE: int = 32

## Noise for `salt`, sampled on a cylinder by `_at` so the map closes east-west with no edge.
static func noise(salt: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = salt
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 5
	n.frequency = 0.035
	return n

## `n` at L3 cell `p`: x goes round a cylinder of L3's width, y along it; about -1..1.
static func _at(n: FastNoiseLite, p: Vector2) -> float:
	var angle := p.x / L3.x * TAU
	var radius := L3.x / TAU
	return n.get_noise_3d(cos(angle) * radius, sin(angle) * radius, p.y)

## The land biomes by heat and humidity: name and map colour. Sea, mountain and snow come from height.
const BIOMES: Array[Array] = [
	["Ice cap", Color8(236, 240, 246)], ["Tundra", Color8(150, 158, 128)], ["Wet tundra", Color8(124, 140, 116)],
	["Cold steppe", Color8(138, 150, 96)], ["Taiga", Color8(66, 104, 72)], ["Dry grassland", Color8(170, 164, 104)],
	["Grassland", Color8(110, 150, 74)], ["Temperate forest", Color8(70, 122, 60)], ["Desert", Color8(214, 186, 122)],
	["Savanna", Color8(170, 168, 86)], ["Tropical forest", Color8(40, 104, 52)]]
## What height alone decides: name and map colour.
const HEIGHTS: Array[Array] = [["Deep sea", Color8(42, 86, 134)], ["Shallow sea", Color8(70, 124, 168)],
	["Sea ice", Color8(214, 226, 238)], ["Mountains", Color8(128, 122, 112)], ["Snow peaks", Color8(240, 242, 246)]]

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

## The biome colour at heat `t` and humidity `m`.
static func biome(t: float, m: float) -> Color:
	return BIOMES[biome_at(t, m)][1]

## The biome lookup the map shader reads: temperature across, moisture down.
static func table() -> Image:
	var image := Image.create_empty(TABLE, TABLE, false, Image.FORMAT_RGB8)
	for y in TABLE:
		for x in TABLE:
			image.set_pixel(x, y, biome((x + 0.5) / TABLE, (y + 0.5) / TABLE))
	return image

## L3's fields, a pixel a cell: R height (Perlin), G heat (latitude bent by noise, colder up high), B humidity (Perlin).
static func l3_fields(salt: int) -> Image:
	var land := noise(salt)
	var warp := noise(salt + 1)
	warp.frequency = 0.02
	var wet := noise(salt + 2)
	wet.frequency = 0.03
	var image := Image.create_empty(L3.x, L3.y, false, Image.FORMAT_RGB8)
	for y in L3.y:
		for x in L3.x:
			var p := Vector2(x + 0.5, y + 0.5)
			var h := clampf(0.5 + _at(land, p) * 1.15, 0.0, 1.0)
			var lat := absf(p.y - L3.y * 0.5) / (L3.y * 0.5)
			var t := 1.0 - lat + _at(warp, p) * 0.45 - maxf(h - SEA, 0.0) * 0.9
			var m := 0.5 + _at(wet, p) * 1.4
			image.set_pixel(x, y, Color(h, clampf(t, 0.0, 1.0), clampf(m, 0.0, 1.0)))
	return image

## L3 cell `cell`'s colour from the fields, as the map shader draws its middle.
static func l3_colour(cell: Vector2i, fields: Image) -> Color:
	var f := fields.get_pixel(posmod(cell.x, L3.x), clampi(cell.y, 0, L3.y - 1))
	if f.r < SEA:
		if f.g < 0.12:
			return HEIGHTS[2][1]
		return HEIGHTS[0][1] if f.r < SEA - 0.05 else HEIGHTS[1][1]
	if f.r > SNOW:
		return HEIGHTS[4][1]
	if f.r > MOUNTAIN:
		return HEIGHTS[3][1]
	return biome(f.g, f.b)

## L2 cell `cell`'s colour: its L3 cell's, a checker of 8-cell blocks, the L3 cell's edge drawn.
static func l2_colour(cell: Vector2i, l3: Image) -> Color:
	var parent := Vector2i(floori(float(cell.x) / SPLIT), floori(float(cell.y) / SPLIT))
	var c := l3_colour(parent, l3)
	var local := Vector2i(posmod(cell.x, SPLIT), posmod(cell.y, SPLIT))
	if local.x == 0 or local.y == 0:
		return c.darkened(0.35)
	return c.darkened(0.06) if ((local.x >> 3) + (local.y >> 3)) % 2 == 0 else c

## L1 cell `cell`'s colour: its L2 cell's, a finer checker, the L2 cell's edge drawn.
static func l1_colour(cell: Vector2i, l3: Image) -> Color:
	var parent := Vector2i(floori(float(cell.x) / SPLIT), floori(float(cell.y) / SPLIT))
	var c := l2_colour(parent, l3)
	var local := Vector2i(posmod(cell.x, SPLIT), posmod(cell.y, SPLIT))
	if local.x == 0 or local.y == 0:
		return c.darkened(0.3)
	return c.lightened(0.08) if ((local.x >> 2) + (local.y >> 2)) % 2 == 0 else c

## A chunk of `level` (1 = L2, 2 = L1) at chunk `at`, `size` cells a side, a pixel a cell, from L3's fields.
static func chunk_image(level: int, at: Vector2i, size: int, l3: Image) -> Image:
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var cell := at * size + Vector2i(x, y)
			image.set_pixel(x, y, l2_colour(cell, l3) if level == 1 else l1_colour(cell, l3))
	return image
