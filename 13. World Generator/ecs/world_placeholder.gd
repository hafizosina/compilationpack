class_name WorldPlaceholder
extends RefCounted

## Step 1's stand-in content, pure and worker-safe: an L3 map of latitude bands and rough continents, and
## L2 and L1 chunks that show their parent cell's colour with a checker, so streaming and levels can be
## seen before real world gen. L2 and L1 colours come from the L3 map and their own cell alone.

## L3's size in cells; east-west wraps.
const L3 := Vector2i(256, 128)
## Child cells per parent cell side.
const SPLIT: int = 128

## Noise for `salt`, sampled on a cylinder by `_at` so the map closes east-west with no edge.
static func noise(salt: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = salt
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 5
	n.frequency = 0.035
	return n

## `n` at L3 cell `p`: x goes round a cylinder of L3's width, y along it; about -1..1.
static func _at(n: FastNoiseLite, p: Vector2) -> float:
	var angle := p.x / L3.x * TAU
	var radius := L3.x / TAU
	return n.get_noise_3d(cos(angle) * radius, sin(angle) * radius, p.y)

## L3 cell `cell`'s colour from noise `n`: sea, or land banded by latitude (ice at both poles).
static func l3_colour(cell: Vector2i, n: FastNoiseLite) -> Color:
	var land := _at(n, Vector2(posmod(cell.x, L3.x), cell.y) + Vector2(0.5, 0.5))
	var lat := absf(float(cell.y) + 0.5 - L3.y * 0.5) / (L3.y * 0.5)
	if lat > 0.86:
		return Color8(232, 238, 244)
	if land < 0.0:
		return Color8(46, 92, 140) if land < -0.08 else Color8(70, 122, 168)
	if lat > 0.68:
		return Color8(140, 150, 120)
	if lat > 0.42:
		return Color8(92, 136, 70)
	if lat > 0.22:
		return Color8(180, 164, 108)
	return Color8(52, 112, 58)

## L2 cell `cell`'s colour: its L3 cell's, a checker of 8-cell blocks, the L3 cell's edge drawn.
static func l2_colour(cell: Vector2i, l3: Image) -> Color:
	var parent := Vector2i(floori(float(cell.x) / SPLIT), floori(float(cell.y) / SPLIT))
	var c := l3.get_pixel(posmod(parent.x, L3.x), clampi(parent.y, 0, L3.y - 1))
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

## The whole L3 map, a pixel a cell.
static func l3_image(salt: int) -> Image:
	var n := noise(salt)
	var image := Image.create_empty(L3.x, L3.y, false, Image.FORMAT_RGB8)
	for y in L3.y:
		for x in L3.x:
			image.set_pixel(x, y, l3_colour(Vector2i(x, y), n))
	return image

## A chunk of `level` (1 = L2, 2 = L1) at chunk `at`, `size` cells a side, a pixel a cell, from the L3 map.
static func chunk_image(level: int, at: Vector2i, size: int, l3: Image) -> Image:
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var cell := at * size + Vector2i(x, y)
			image.set_pixel(x, y, l2_colour(cell, l3) if level == 1 else l1_colour(cell, l3))
	return image
