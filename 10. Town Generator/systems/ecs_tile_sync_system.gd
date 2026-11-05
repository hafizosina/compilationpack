class_name EcsTileSyncSystem
extends EcsSystem

## Draws the grid onto the scene's TileMapLayers, one way; it never creates a layer.
## Each terrain and floor def names its layer, configured in the scene with its TileSet,
## half-cell offset and scale; a layer's place among its siblings is its draw order, and
## a type's layer also fills under every later type so edges blend. Walls go on the wall
## layer's cell grid, one atlas source per wall type, joined to its building's neighbouring walls.
## The first run clears and draws all; after that only what changed is redrawn.

## A tile's transform flags for 0-3 quarter turns clockwise.
const TURN_FLAGS: Array[int] = [
	0,
	TileSetAtlasSource.TRANSFORM_TRANSPOSE | TileSetAtlasSource.TRANSFORM_FLIP_H,
	TileSetAtlasSource.TRANSFORM_FLIP_H | TileSetAtlasSource.TRANSFORM_FLIP_V,
	TileSetAtlasSource.TRANSFORM_TRANSPOSE | TileSetAtlasSource.TRANSFORM_FLIP_V,
]

var _layers_root: Node
var _catalog: EcsTownCatalog
var _built: bool = false
## Per group, in draw order: defs, their layers, and each layer's corner layout.
var _terrain_defs: Array[EcsTileDef] = []
var _floor_defs: Array[EcsTileDef] = []
var _terrain_layers: Array[TileMapLayer] = []
var _floor_layers: Array[TileMapLayer] = []
var _roof_defs: Array[EcsTileDef] = []
var _roof_layers: Array[TileMapLayer] = []
var _layouts: Dictionary = {}
## Catalog id -> draw order.
var _terrain_rank: Dictionary = {}
var _floor_rank: Dictionary = {}
var _roof_rank: Dictionary = {}
var _wall_layer: TileMapLayer
var _furniture_layer: TileMapLayer
var _attachment_layer: TileMapLayer
## Wall type id -> [source id, side layout].
var _wall_sources: Dictionary = {}
## The world of the current run, for a door's open state.
var _world: EcsWorld
## Tiles written on the last run, and the microseconds it took.
var redrawn: int = 0
var last_usec: int = 0

func _init(layers_root: Node, catalog: EcsTownCatalog) -> void:
	_layers_root = layers_root
	_catalog = catalog

func label() -> StringName:
	return &"tile_sync"

func run(world: EcsWorld, _delta: float) -> void:
	var grid := world.get_singleton(EcsTownGridSingleton) as EcsTownGridSingleton
	if grid == null or _layers_root == null:
		return
	if _built and grid.dirty.is_empty():
		redrawn = 0
		return
	var started := Time.get_ticks_usec()
	redrawn = 0
	_world = world
	if not _built:
		_build()
		_draw_all(grid)
	else:
		_draw_dirty(grid)
	grid.dirty.clear()
	last_usec = Time.get_ticks_usec() - started

func terrain_layers() -> Array[TileMapLayer]:
	return _terrain_layers

func floor_layers() -> Array[TileMapLayer]:
	return _floor_layers

func roof_layers() -> Array[TileMapLayer]:
	return _roof_layers

func wall_layer() -> TileMapLayer:
	return _wall_layer

## Which quarters the tile at `at` on a terrain or floor layer fills; 0 when empty.
func mask_at(layer: TileMapLayer, at: Vector2i) -> int:
	if layer.get_cell_source_id(at) == -1:
		return 0
	return EcsDualGrid.mask_of(_layouts[layer], layer.get_cell_atlas_coords(at))

## The door tile at `cell` as [source id, atlas coords], or [] when there is none.
func door_tile_at(cell: Vector2i) -> Array:
	var source := _wall_layer.get_cell_source_id(cell)
	for def in _catalog.doors:
		if source == def.closed_source_id or source == def.open_source_id:
			return [source, _wall_layer.get_cell_atlas_coords(cell)]
	return []

## Which sides the wall at `cell` joins; -1 when there is none.
func wall_mask_at(cell: Vector2i) -> int:
	var source := _wall_layer.get_cell_source_id(cell)
	for type: int in _wall_sources:
		if (_wall_sources[type] as Array)[0] == source:
			return EcsDualGrid.mask_of((_wall_sources[type] as Array)[1], _wall_layer.get_cell_atlas_coords(cell))
	return -1

func _build() -> void:
	_catalog.number()
	_collect(_catalog.terrains, _terrain_defs, _terrain_layers, _terrain_rank)
	_collect(_catalog.floors, _floor_defs, _floor_layers, _floor_rank)
	_collect(_catalog.roofs, _roof_defs, _roof_layers, _roof_rank)
	_furniture_layer = _layers_root.get_node_or_null(NodePath(_catalog.furniture_layer)) as TileMapLayer
	_attachment_layer = _layers_root.get_node_or_null(NodePath(_catalog.attachment_layer)) as TileMapLayer
	for layer in [_furniture_layer, _attachment_layer]:
		if layer != null:
			(layer as TileMapLayer).clear()
	_wall_layer = _layers_root.get_node_or_null(NodePath(_catalog.wall_layer)) as TileMapLayer
	if _wall_layer == null:
		push_error("EcsTileSyncSystem: no wall layer '%s' in the scene" % _catalog.wall_layer)
	else:
		_wall_layer.clear()
		for def in _catalog.walls:
			var source := _wall_layer.tile_set.get_source(def.source_id) as TileSetAtlasSource \
				if _wall_layer.tile_set.has_source(def.source_id) else null
			if source == null:
				push_error("EcsTileSyncSystem: wall '%s' names source %d, not in %s's TileSet"
					% [def.display_name, def.source_id, _wall_layer.name])
				continue
			_wall_sources[def.id] = [def.source_id, EcsDualGrid.side_layout(source)]
	_built = true

## Finds each def's layer in the scene, orders them as the scene does, and reads layouts.
func _collect(defs: Array, out_defs: Array[EcsTileDef], out_layers: Array[TileMapLayer],
		rank: Dictionary) -> void:
	var found: Array = []
	for def: EcsTileDef in defs:
		var layer := _layers_root.get_node_or_null(NodePath(def.layer)) as TileMapLayer
		if layer == null:
			push_error("EcsTileSyncSystem: no TileMapLayer '%s' for '%s'" % [def.layer, def.display_name])
			continue
		if not layer.position.is_equal_approx(-Vector2.ONE * EcsTownGrid.CELL * 0.5):
			push_warning("EcsTileSyncSystem: %s should sit at (-16, -16), half a cell, for the dual grid" % layer.name)
		found.append([layer.get_index(), def, layer])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for entry: Array in found:
		var def := entry[1] as EcsTileDef
		var layer := entry[2] as TileMapLayer
		rank[def.id] = out_defs.size()
		out_defs.append(def)
		out_layers.append(layer)
		layer.clear()
		_layouts[layer] = EcsDualGrid.corner_layout(layer.tile_set.get_source(layer.tile_set.get_source_id(0)))

func _draw_all(grid: EcsTownGridSingleton) -> void:
	for y in grid.height + 1:
		for x in grid.width + 1:
			_draw_at(grid, Vector2i(x, y), true, true, false)
	for y in grid.height:
		for x in grid.width:
			_draw_wall(grid, Vector2i(x, y))
			_draw_objects(grid, Vector2i(x, y))

func _draw_dirty(grid: EcsTownGridSingleton) -> void:
	var terrain_tiles: Dictionary = {}
	var floor_tiles: Dictionary = {}
	var roof_tiles: Dictionary = {}
	var wall_cells: Dictionary = {}
	var object_cells: Dictionary = {}
	for i: int in grid.dirty:
		var bits: int = grid.dirty[i]
		var cell := Vector2i(i % grid.width, i / grid.width)
		for corner in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			if bits & EcsTownGridSingleton.CHANGED_TERRAIN:
				terrain_tiles[cell + corner] = true
			if bits & EcsTownGridSingleton.CHANGED_FLOOR:
				floor_tiles[cell + corner] = true
			if bits & EcsTownGridSingleton.CHANGED_ROOF:
				roof_tiles[cell + corner] = true
		if bits & EcsTownGridSingleton.CHANGED_OBJECT:
			wall_cells[cell] = true
			object_cells[cell] = true
		if bits & EcsTownGridSingleton.CHANGED_STRUCTURE:
			wall_cells[cell] = true
			for side in EcsDualGrid.SIDES:
				wall_cells[cell + side] = true
	for at: Vector2i in terrain_tiles:
		_draw_at(grid, at, true, false, true)
	for at: Vector2i in floor_tiles:
		_draw_at(grid, at, false, true, true)
	for at: Vector2i in roof_tiles:
		var around := _around(grid, at, grid.roof, _roof_rank, false)
		for k in _roof_layers.size():
			_put(_roof_layers[k], at, _mask(around, k), true)
	for cell: Vector2i in wall_cells:
		if EcsTownGrid.in_bounds(grid, cell):
			_draw_wall(grid, cell)
	for cell: Vector2i in object_cells:
		_draw_objects(grid, cell)

## Redraws render tile `at` on the chosen groups. `erase` clears tiles whose mask became
## empty; a first draw has nothing to clear.
func _draw_at(grid: EcsTownGridSingleton, at: Vector2i, terrain: bool, floors: bool, erase: bool) -> void:
	if terrain:
		var around := _around(grid, at, grid.terrain, _terrain_rank, true)
		for k in _terrain_layers.size():
			_put(_terrain_layers[k], at, _mask(around, k), erase)
	if floors:
		var around := _around(grid, at, grid.floor, _floor_rank, false)
		for k in _floor_layers.size():
			_put(_floor_layers[k], at, _mask(around, k), erase)

## Draw order of the four cells around render tile `at`, TL, TR, BL, BR; -1 for none.
## Off the map, terrain repeats the edge cell and floor is none.
func _around(grid: EcsTownGridSingleton, at: Vector2i, cells: PackedInt32Array,
		rank: Dictionary, clamp_edges: bool) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(4)
	for q in 4:
		var cell: Vector2i = at + EcsDualGrid.CORNERS[q]
		if not EcsTownGrid.in_bounds(grid, cell):
			if not clamp_edges:
				out[q] = -1
				continue
			cell = cell.clamp(Vector2i.ZERO, Vector2i(grid.width - 1, grid.height - 1))
		var id := cells[EcsTownGrid.index(grid, cell)]
		out[q] = int(rank.get(id, -1)) if id != 0 else -1
	return out

## Quarters whose cell's type draws at or after layer `k`.
func _mask(around: PackedInt32Array, k: int) -> int:
	var mask := 0
	for q in 4:
		if around[q] >= k:
			mask |= EcsDualGrid.BITS[q]
	return mask

func _put(layer: TileMapLayer, at: Vector2i, mask: int, erase: bool) -> void:
	if mask == 0:
		if erase:
			layer.erase_cell(at)
			redrawn += 1
		return
	layer.set_cell(at, layer.tile_set.get_source_id(0), EcsDualGrid.atlas_for(_layouts[layer], mask, at))
	redrawn += 1

## A wall joins each neighbouring wall of its own building — not a door, so a wall beside
## a door ends in a post; a touching building's walls stay apart.
func _draw_wall(grid: EcsTownGridSingleton, cell: Vector2i) -> void:
	if _wall_layer == null:
		return
	var i := EcsTownGrid.index(grid, cell)
	if grid.structure[i] == EcsTownGridSingleton.DOOR:
		_draw_door(grid, cell, i)
		return
	var entry: Array = _wall_sources.get(grid.wall_type[i], [])
	if grid.structure[i] != EcsTownGridSingleton.WALL or entry.is_empty():
		if _wall_layer.get_cell_source_id(cell) != -1:
			_wall_layer.erase_cell(cell)
			redrawn += 1
		return
	var mask := 0
	for k in 4:
		var next: Vector2i = cell + EcsDualGrid.SIDES[k]
		if not EcsTownGrid.in_bounds(grid, next):
			continue
		var n := EcsTownGrid.index(grid, next)
		if grid.structure[n] == EcsTownGridSingleton.WALL and grid.building_id[n] == grid.building_id[i]:
			mask |= EcsDualGrid.SIDE_BITS[k]
	_wall_layer.set_cell(cell, entry[0], EcsDualGrid.atlas_for(entry[1], mask, cell))
	redrawn += 1

## A door lies along its wall: horizontal when a wall or door of its building is beside it
## left or right. Open or closed comes from its entity; until that is born, closed.
func _draw_door(grid: EcsTownGridSingleton, cell: Vector2i, i: int) -> void:
	var def := _catalog.door(grid.wall_type[i])
	if def == null:
		_wall_layer.erase_cell(cell)
		return
	var horizontal := false
	for side in [Vector2i.LEFT, Vector2i.RIGHT]:
		var next: Vector2i = cell + side
		if EcsTownGrid.in_bounds(grid, next):
			var n := EcsTownGrid.index(grid, next)
			if grid.structure[n] != EcsTownGridSingleton.NONE and grid.building_id[n] == grid.building_id[i]:
				horizontal = true
	var id := grid.object_id[i]
	var door := _world.get_component(id, EcsDoorComponent) as EcsDoorComponent \
		if _world != null and id > EcsWorld.NO_ENTITY else null
	if door != null and door.is_open:
		_wall_layer.set_cell(cell, def.open_source_id, def.open_horizontal if horizontal else def.open_vertical)
	else:
		_wall_layer.set_cell(cell, def.closed_source_id, def.closed_horizontal if horizontal else def.closed_vertical)
	redrawn += 1

## The furniture or plant covering `cell` — its slice of the piece's tiles — and the
## attachment in the cell's slot. Doors are the wall layer's; unborn things draw nothing yet.
func _draw_objects(grid: EcsTownGridSingleton, cell: Vector2i) -> void:
	var i := EcsTownGrid.index(grid, cell)
	if _furniture_layer != null:
		_draw_entity_tile(_furniture_layer, cell, grid.object_id[i])
	if _attachment_layer != null:
		_draw_entity_tile(_attachment_layer, cell, grid.attachment_id[i])

func _draw_entity_tile(layer: TileMapLayer, cell: Vector2i, id: int) -> void:
	var tile := _world.get_component(id, EcsTileComponent) as EcsTileComponent \
		if _world != null and id > EcsWorld.NO_ENTITY else null
	if tile == null:
		if layer.get_cell_source_id(cell) != -1:
			layer.erase_cell(cell)
			redrawn += 1
		return
	var place := _world.get_component(id, EcsGridPositionComponent) as EcsGridPositionComponent
	if place == null:
		layer.set_cell(cell, tile.source_id, tile.atlas)
	else:
		# A turned piece draws, on each cell, the slice that turned there, turned the same.
		var offset := EcsTownGrid.turn(cell - place.cell, place.size, 4 - place.turns)
		layer.set_cell(cell, tile.source_id, tile.atlas + offset, TURN_FLAGS[posmod(place.turns, 4)])
	redrawn += 1
