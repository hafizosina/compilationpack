class_name EcsDualGrid
extends RefCounted

## Tile layouts, read from a TileSet's atlas source. Terrain and floor use the dual grid:
## tiles sit on a grid offset half a cell, so each render tile is centred on a cell corner
## and shows a quarter of each of its four cells. Render tile (x, y) covers cells
## (x-1, y-1) TL, (x, y-1) TR, (x-1, y) BL and (x, y) BR. Walls use the cell grid and
## connect by side.

## Corner bits of a dual-grid mask.
const TL: int = 8
const TR: int = 4
const BL: int = 2
const BR: int = 1
const FULL: int = 15
## Side bits of a wall mask.
const RIGHT: int = 1
const BOTTOM: int = 2
const LEFT: int = 4
const TOP: int = 8

## The cells a render tile covers, as offsets from it, in TL, TR, BL, BR order.
const CORNERS: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]
const BITS: Array[int] = [TL, TR, BL, BR]
## A wall's neighbours and the side bit each sets.
const SIDES: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
const SIDE_BITS: Array[int] = [RIGHT, BOTTOM, LEFT, TOP]

## Fallback layouts, those of WoodFloor.png and WoodWall.png: mask -> atlas coords.
const CORNER_ATLAS: Dictionary = {
	BR: [Vector2i(0, 0)], BL | BR: [Vector2i(1, 0)], BL: [Vector2i(2, 0)],
	TL | TR | BL: [Vector2i(3, 0)], TL | TR | BR: [Vector2i(4, 0)], TL | BR: [Vector2i(5, 0)],
	TR | BR: [Vector2i(0, 1)], TL | BL: [Vector2i(2, 1)],
	TL | BL | BR: [Vector2i(3, 1)], TR | BL | BR: [Vector2i(4, 1)], TR | BL: [Vector2i(5, 1)],
	TR: [Vector2i(0, 2)], TL | TR: [Vector2i(1, 2)], TL: [Vector2i(2, 2)],
	FULL: [Vector2i(1, 1), Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2)],
}
const SIDE_ATLAS: Dictionary = {
	RIGHT | BOTTOM: [Vector2i(0, 0)], RIGHT | LEFT: [Vector2i(1, 0), Vector2i(1, 2)],
	BOTTOM | LEFT: [Vector2i(2, 0)], RIGHT: [Vector2i(3, 0)], RIGHT | BOTTOM | LEFT: [Vector2i(4, 0)],
	BOTTOM: [Vector2i(5, 0)], BOTTOM | TOP: [Vector2i(0, 1), Vector2i(2, 1)], 0: [Vector2i(1, 1)],
	RIGHT | BOTTOM | TOP: [Vector2i(3, 1)], RIGHT | BOTTOM | LEFT | TOP: [Vector2i(4, 1)],
	BOTTOM | LEFT | TOP: [Vector2i(5, 1)], RIGHT | TOP: [Vector2i(0, 2)], LEFT | TOP: [Vector2i(2, 2)],
	TOP: [Vector2i(3, 2)], RIGHT | LEFT | TOP: [Vector2i(4, 2)], LEFT: [Vector2i(5, 2)],
}

## A TileSet of `texture` cut into `tile_size` tiles, every tile of the sheet in source 0.
static func make_tile_set(texture: Texture2D, tile_size: int) -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(tile_size, tile_size)
	tile_set.add_source(make_source(texture, tile_size), 0)
	return tile_set

## An atlas source of `texture` cut into `tile_size` tiles after `margins`, every tile that fits.
static func make_source(texture: Texture2D, tile_size: int, margins: Vector2i = Vector2i.ZERO) -> TileSetAtlasSource:
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.margins = margins
	source.texture_region_size = Vector2i(tile_size, tile_size)
	var tiles := (Vector2i(texture.get_size()) - margins) / tile_size
	for y in tiles.y:
		for x in tiles.x:
			source.create_tile(Vector2i(x, y))
	return source

## Corner layout of `source`: from its terrain peering bits when the author painted them,
## else from transparency (a quarter counts when over half of it is opaque), else the fallback.
static func corner_layout(source: TileSetAtlasSource) -> Dictionary:
	var peering := [TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER, TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER,
		TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER]
	var layout := _from_peering(source, peering, BITS, false)
	if layout.size() < 15:
		layout = _from_pixels(source, false)
	if layout.size() < 15:
		push_warning("EcsDualGrid: %s reads %d of 15 corner masks; using WoodFloor's layout"
			% [source.texture.resource_path, layout.size()])
		return CORNER_ATLAS
	return layout

## Side layout of `source`, for walls: peering bits, else transparency at each edge's middle,
## else the fallback. Mask 0 is a lone post.
static func side_layout(source: TileSetAtlasSource) -> Dictionary:
	var peering := [TileSet.CELL_NEIGHBOR_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_SIDE,
		TileSet.CELL_NEIGHBOR_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_SIDE]
	var layout := _from_peering(source, peering, SIDE_BITS, true)
	if layout.size() < 16:
		layout = _from_pixels(source, true)
	if layout.size() < 16:
		push_warning("EcsDualGrid: %s reads %d of 16 side masks; using WoodWall's layout"
			% [source.texture.resource_path, layout.size()])
		return SIDE_ATLAS
	return layout

## Atlas coords for `mask` at `at`; variants pick by position, the same every time.
static func atlas_for(layout: Dictionary, mask: int, at: Vector2i) -> Vector2i:
	var options: Array = layout[mask]
	if options.size() == 1:
		return options[0]
	return options[absi((at.x * 73856093) ^ (at.y * 19349663)) % options.size()]

## The mask of an atlas tile in `layout`, or -1 if it has none.
static func mask_of(layout: Dictionary, atlas: Vector2i) -> int:
	for mask: int in layout:
		if (layout[mask] as Array).has(atlas):
			return mask
	return -1

## Tiles with a terrain set, masked by which peering bits name the tile's own terrain.
static func _from_peering(source: TileSetAtlasSource, peering: Array, bits: Array[int],
		keep_empty: bool) -> Dictionary:
	var layout: Dictionary = {}
	for i in source.get_tiles_count():
		var coords := source.get_tile_id(i)
		var data := source.get_tile_data(coords, 0)
		if data == null or data.terrain_set < 0:
			continue
		var mask := 0
		for k in 4:
			if data.is_valid_terrain_peering_bit(peering[k]) \
					and data.get_terrain_peering_bit(peering[k]) >= 0 \
					and (data.terrain < 0 or data.get_terrain_peering_bit(peering[k]) == data.terrain):
				mask |= bits[k]
		if mask == 0 and not keep_empty:
			continue
		if not layout.has(mask):
			layout[mask] = []
		(layout[mask] as Array).append(coords)
	return layout

static func _from_pixels(source: TileSetAtlasSource, sides: bool) -> Dictionary:
	var image := source.texture.get_image()
	if image == null:
		return {}
	if image.is_compressed():
		image.decompress()
	var size := source.texture_region_size.x
	var half := size / 2
	var layout: Dictionary = {}
	for i in source.get_tiles_count():
		var coords := source.get_tile_id(i)
		var origin := source.get_tile_texture_region(coords).position
		var mask := 0
		var solid := false
		if sides:
			# A side connects when the middle of that edge is opaque.
			var probes := [Vector2i(size - 2, half), Vector2i(half, size - 2), Vector2i(1, half), Vector2i(half, 1)]
			for k in 4:
				if image.get_pixelv(origin + probes[k]).a > 0.5:
					mask |= SIDE_BITS[k]
			solid = image.get_pixelv(origin + Vector2i(half, half)).a > 0.5
		else:
			for q in 4:
				var opaque := 0
				var corner := origin + Vector2i((q % 2) * half, (q / 2) * half)
				for y in half:
					for x in half:
						if image.get_pixel(corner.x + x, corner.y + y).a > 0.5:
							opaque += 1
				if opaque * 2 > half * half:
					mask |= BITS[q]
			solid = mask != 0
		if not solid:
			continue
		if not layout.has(mask):
			layout[mask] = []
		(layout[mask] as Array).append(coords)
	return layout
