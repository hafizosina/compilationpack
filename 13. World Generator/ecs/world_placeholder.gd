class_name WorldPlaceholder
extends RefCounted

## Stand-in L2 and L1 chunks until they are generated for real: each cell shows its parent's colour with a
## checker and the parent cell's edge drawn, so streaming and levels can be seen. Pure and worker-safe.

## Child cells per parent cell side.
const SPLIT: int = 128

## L2 cell `cell`'s colour: its L3 cell's, a checker of 8-cell blocks, the L3 cell's edge drawn.
static func l2_colour(cell: Vector2i, map: WorldMap) -> Color:
	var c := map.colour(Vector2i(floori(float(cell.x) / SPLIT), floori(float(cell.y) / SPLIT)))
	var local := Vector2i(posmod(cell.x, SPLIT), posmod(cell.y, SPLIT))
	if local.x == 0 or local.y == 0:
		return c.darkened(0.35)
	return c.darkened(0.06) if ((local.x >> 3) + (local.y >> 3)) % 2 == 0 else c

## L1 cell `cell`'s colour: its L2 cell's, a finer checker, the L2 cell's edge drawn.
static func l1_colour(cell: Vector2i, map: WorldMap) -> Color:
	var c := l2_colour(Vector2i(floori(float(cell.x) / SPLIT), floori(float(cell.y) / SPLIT)), map)
	var local := Vector2i(posmod(cell.x, SPLIT), posmod(cell.y, SPLIT))
	if local.x == 0 or local.y == 0:
		return c.darkened(0.3)
	return c.lightened(0.08) if ((local.x >> 2) + (local.y >> 2)) % 2 == 0 else c

## A chunk of `level` (1 = L2, 2 = L1) at chunk `at`, `size` cells a side, a pixel a cell.
static func chunk_image(level: int, at: Vector2i, size: int, map: WorldMap) -> Image:
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var cell := at * size + Vector2i(x, y)
			image.set_pixel(x, y, l2_colour(cell, map) if level == 1 else l1_colour(cell, map))
	return image
