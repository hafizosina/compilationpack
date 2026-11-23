class_name EcsTileSyncSystem
extends EcsSystem

## Draws the grid, one way, under its root: the ground, one sprite whose texture holds each cell's
## terrain and whose shader (art/ground.gdshader) shows the terrains' large textures with soft
## edges; the floors likewise (art/floor.gdshader: rigid edges, a path's ragged, a floor running
## under walls to their middle); then furniture, doors (their own layer, under the walls), walls and
## attachments on the cell grid, their sheets added as sources; then a TileMapLayer per roof type,
## half a cell up and left for the dual grid, in list order, a type's layer also filling under every
## later type. Walls use one atlas source per wall type, joined to their building's neighbouring
## walls. The root is its own: the first run clears it, builds and draws all; after that only what
## changed is redrawn.

const GROUND_SHADER := preload("res://10. Town Generator/art/ground.gdshader")
const FLOOR_SHADER := preload("res://10. Town Generator/art/floor.gdshader")
## Added to a floor pixel on a wall or door cell: the shader shows the floor round it there, not its own.
const WALLED: int = 128

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
## The ground: one pixel a cell, its terrain's draw order + 1.
var _ground: Sprite2D
var _ground_image: Image
var _ground_texture: ImageTexture
## The floors: one pixel a cell, its floor's draw order + 1, WALLED added under a wall or door.
var _floors: Sprite2D
var _floor_image: Image
var _floor_texture: ImageTexture
var _roof_defs: Array[EcsTileDef] = []
var _roof_layers: Array[TileMapLayer] = []
var _layouts: Dictionary = {}
## Catalog id -> draw order.
var _terrain_rank: Dictionary = {}
var _floor_rank: Dictionary = {}
var _roof_rank: Dictionary = {}
var _wall_layer: TileMapLayer
## Doors, on their own layer just under the walls, so a door always lies under the posts either side.
var _door_layer: TileMapLayer
var _furniture_layer: TileMapLayer
var _attachment_layer: TileMapLayer
## Wall type id -> [source id, side layout].
var _wall_sources: Dictionary = {}
## [layer, texture, tile size] -> source id, for furniture and attachment sheets.
var _sheet_sources: Dictionary = {}
## Whether the roof layers show.
var roofs_visible: bool = true:
	set(on):
		roofs_visible = on
		for layer in _roof_layers:
			layer.visible = on
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
		_build(grid)
		_draw_all(grid)
	else:
		_draw_dirty(grid)
	grid.dirty.clear()
	last_usec = Time.get_ticks_usec() - started

## The ground sprite: its texture is one pixel a cell.
func ground() -> Sprite2D:
	return _ground

## The draw order of the terrain shown at `cell`, as the ground holds it; -1 off the ground or for none.
func ground_rank_at(cell: Vector2i) -> int:
	if _ground_image == null or not Rect2i(Vector2i.ZERO, _ground_image.get_size()).has_point(cell):
		return -1
	return roundi(_ground_image.get_pixelv(cell).r * 255.0) - 1

## The floors sprite: its texture is one pixel a cell.
func floors() -> Sprite2D:
	return _floors

## The draw order of the floor shown at `point` (in cells), as the floor shader decides it: a wall's
## quarter takes the highest floor of the open cells round its corner; -1 for none.
func floor_shown_at(point: Vector2) -> int:
	var c := Vector2i(point.floor())
	var v := _floor_raw(c)
	if v < WALLED:
		return v - 1
	var f := point - Vector2(c)
	var d := Vector2i(-1 if f.x < 0.5 else 1, -1 if f.y < 0.5 else 1)
	var best := -1
	for n: Vector2i in [c + Vector2i(d.x, 0), c + Vector2i(0, d.y), c + d]:
		var w := _floor_raw(n)
		if w < WALLED:
			best = maxi(best, w - 1)
	return best

func _floor_raw(cell: Vector2i) -> int:
	if _floor_image == null or not Rect2i(Vector2i.ZERO, _floor_image.get_size()).has_point(cell):
		return 0
	return roundi(_floor_image.get_pixelv(cell).r * 255.0)

func roof_layers() -> Array[TileMapLayer]:
	return _roof_layers

func wall_layer() -> TileMapLayer:
	return _wall_layer

func door_layer() -> TileMapLayer:
	return _door_layer

func furniture_layer() -> TileMapLayer:
	return _furniture_layer

func attachment_layer() -> TileMapLayer:
	return _attachment_layer

## Which quarters the tile at `at` on a roof layer fills; 0 when empty.
func mask_at(layer: TileMapLayer, at: Vector2i) -> int:
	if layer.get_cell_source_id(at) == -1:
		return 0
	return EcsDualGrid.mask_of(_layouts[layer], layer.get_cell_atlas_coords(at))

## The door tile at `cell` as [source id, atlas coords], or [] when there is none.
func door_tile_at(cell: Vector2i) -> Array:
	var source := _door_layer.get_cell_source_id(cell)
	for def in _catalog.doors:
		if source == def.closed_source_id or source == def.open_source_id:
			return [source, _door_layer.get_cell_atlas_coords(cell)]
	return []

## Which sides the wall at `cell` joins; -1 when there is none.
func wall_mask_at(cell: Vector2i) -> int:
	var source := _wall_layer.get_cell_source_id(cell)
	for type: int in _wall_sources:
		if (_wall_sources[type] as Array)[0] == source:
			return EcsDualGrid.mask_of((_wall_sources[type] as Array)[1], _wall_layer.get_cell_atlas_coords(cell))
	return -1

func _build(grid: EcsTownGridSingleton) -> void:
	_catalog.number()
	for child in _layers_root.get_children():
		_layers_root.remove_child(child)
		child.queue_free()
	_make_ground(grid)
	_make_floors(grid)
	_furniture_layer = _make_layer("Furniture", _cell_tile_set(), false)
	_door_layer = _make_layer("Doors", _catalog.wall_tiles(), false)
	_wall_layer = _make_layer("Walls", _catalog.wall_tiles(), false)
	_attachment_layer = _make_layer("Attachments", _cell_tile_set(), false)
	_collect(_catalog.roofs, _roof_defs, _roof_layers, _roof_rank, "Roof")
	roofs_visible = roofs_visible
	if _wall_layer != null:
		for def in _catalog.walls:
			var source := _wall_layer.tile_set.get_source(def.source_id) as TileSetAtlasSource \
				if _wall_layer.tile_set.has_source(def.source_id) else null
			if source == null:
				push_error("EcsTileSyncSystem: wall '%s' has no sheet" % def.key)
				continue
			_wall_sources[def.id] = [def.source_id, EcsDualGrid.side_layout(source)]
	_built = true

## An empty TileSet on the cell grid at EcsTownGrid.ART pixels a cell; pieces add their sheets
## as they are first drawn.
func _cell_tile_set() -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(EcsTownGrid.ART, EcsTownGrid.ART)
	return tile_set

## The source on `layer` for `tile`'s sheet, added the first time that sheet is drawn.
func _source_for(layer: TileMapLayer, tile: EcsTileComponent) -> int:
	var key := [layer, tile.texture, tile.tile_size]
	if not _sheet_sources.has(key):
		_sheet_sources[key] = layer.tile_set.add_source(EcsDualGrid.make_source(tile.texture, tile.tile_size))
	return _sheet_sources[key]

## The ground sprite, a grid-sized texture scaled up a cell a pixel, drawn by the ground shader.
func _make_ground(grid: EcsTownGridSingleton) -> void:
	for k in _catalog.terrains.size():
		_terrain_rank[_catalog.terrains[k].id] = k
	_ground_image = Image.create_empty(grid.width, grid.height, false, Image.FORMAT_R8)
	_ground_texture = ImageTexture.create_from_image(_ground_image)
	_ground = _map_sprite("Ground", _ground_texture, GROUND_SHADER, {
		&"grounds": _catalog.grounds(), &"count": _catalog.terrains.size()})

## The floors sprite, like the ground's, drawn by the floor shader.
func _make_floors(grid: EcsTownGridSingleton) -> void:
	var soft := 0
	for k in _catalog.floors.size():
		_floor_rank[_catalog.floors[k].id] = k
		if _catalog.floors[k].soft:
			soft |= 1 << k
	_floor_image = Image.create_empty(grid.width, grid.height, false, Image.FORMAT_R8)
	_floor_texture = ImageTexture.create_from_image(_floor_image)
	_floors = _map_sprite("Floors", _floor_texture, FLOOR_SHADER, {
		&"map": _floor_texture, &"surfaces": _catalog.surfaces(), &"count": _catalog.floors.size(), &"soft_mask": soft})

## A sprite of `texture` (a pixel a cell) scaled up to the grid, drawn by `shader` with `params`.
func _map_sprite(sprite_name: String, texture: ImageTexture, shader: Shader, params: Dictionary) -> Sprite2D:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter(&"cell", float(EcsTownGrid.CELL))
	material.set_shader_parameter(&"cells_per_texture", float(EcsTownCatalog.GROUND_SIZE) / EcsTownGrid.ART)
	for key: StringName in params:
		material.set_shader_parameter(key, params[key])
	var sprite := Sprite2D.new()
	sprite.name = sprite_name
	sprite.texture = texture
	sprite.centered = false
	sprite.scale = Vector2(EcsTownGrid.CELL, EcsTownGrid.CELL)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.material = material
	_layers_root.add_child(sprite)
	return sprite

## Writes `cell`'s floor, and whether a wall or door stands on it, into the floor image; true when it changed.
func _put_floor(grid: EcsTownGridSingleton, cell: Vector2i) -> bool:
	var i := EcsTownGrid.index(grid, cell)
	var id := grid.floor[i]
	var value := int(_floor_rank.get(id, -1)) + 1 if id != 0 else 0
	if grid.structure[i] != EcsTownGridSingleton.NONE:
		value += WALLED
	if _floor_raw(cell) == value:
		return false
	_floor_image.set_pixelv(cell, Color(value / 255.0, 0, 0))
	return true

## Writes `cell`'s terrain into the ground image; true when it changed.
func _put_ground(grid: EcsTownGridSingleton, cell: Vector2i) -> bool:
	var id := grid.terrain[EcsTownGrid.index(grid, cell)]
	var value := (int(_terrain_rank.get(id, -1)) + 1) / 255.0 if id != 0 else 0.0
	if is_equal_approx(_ground_image.get_pixelv(cell).r, value):
		return false
	_ground_image.set_pixelv(cell, Color(value, 0, 0))
	return true

## A layer per def, in list order, and each one's corner layout.
func _collect(defs: Array, out_defs: Array[EcsTileDef], out_layers: Array[TileMapLayer],
		rank: Dictionary, group: String) -> void:
	for def: EcsTileDef in defs:
		var layer := _make_layer("%s_%s" % [group, def.key], _catalog.tiles(def), true)
		if layer == null:
			continue
		rank[def.id] = out_defs.size()
		out_defs.append(def)
		out_layers.append(layer)
		_layouts[layer] = EcsDualGrid.corner_layout(layer.tile_set.get_source(layer.tile_set.get_source_id(0)))

## A layer drawing `tile_set`, scaled so a tile spans one cell; on the dual grid, half a cell
## up and left, so render tile (x, y) is centred on the corner its four cells share.
func _make_layer(layer_name: String, tile_set: TileSet, dual: bool) -> TileMapLayer:
	if tile_set == null:
		push_error("EcsTileSyncSystem: no tiles for %s" % layer_name)
		return null
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = tile_set
	layer.scale = Vector2.ONE * EcsTownGrid.CELL / Vector2(tile_set.tile_size)
	if dual:
		layer.position = -Vector2.ONE * EcsTownGrid.CELL * 0.5
	_layers_root.add_child(layer)
	return layer

func _draw_all(grid: EcsTownGridSingleton) -> void:
	for y in grid.height:
		for x in grid.width:
			if _put_ground(grid, Vector2i(x, y)):
				redrawn += 1
	_ground_texture.update(_ground_image)
	for y in grid.height:
		for x in grid.width:
			if _put_floor(grid, Vector2i(x, y)):
				redrawn += 1
	_floor_texture.update(_floor_image)
	for y in grid.height:
		for x in grid.width:
			_draw_wall(grid, Vector2i(x, y))
			_draw_objects(grid, Vector2i(x, y))

func _draw_dirty(grid: EcsTownGridSingleton) -> void:
	var ground_changed := false
	var floors_changed := false
	var roof_tiles: Dictionary = {}
	var wall_cells: Dictionary = {}
	var object_cells: Dictionary = {}
	for i: int in grid.dirty:
		var bits: int = grid.dirty[i]
		var cell := Vector2i(i % grid.width, i / grid.width)
		if bits & EcsTownGridSingleton.CHANGED_TERRAIN and _put_ground(grid, cell):
			ground_changed = true
			redrawn += 1
		if bits & (EcsTownGridSingleton.CHANGED_FLOOR | EcsTownGridSingleton.CHANGED_STRUCTURE) and _put_floor(grid, cell):
			floors_changed = true
			redrawn += 1
		for corner in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			if bits & EcsTownGridSingleton.CHANGED_ROOF:
				roof_tiles[cell + corner] = true
		if bits & EcsTownGridSingleton.CHANGED_OBJECT:
			wall_cells[cell] = true
			object_cells[cell] = true
		if bits & EcsTownGridSingleton.CHANGED_STRUCTURE:
			wall_cells[cell] = true
			for side in EcsDualGrid.SIDES:
				wall_cells[cell + side] = true
	if ground_changed:
		_ground_texture.update(_ground_image)
	if floors_changed:
		_floor_texture.update(_floor_image)
	for at: Vector2i in roof_tiles:
		var around := _around(grid, at, grid.roof, _roof_rank)
		for k in _roof_layers.size():
			_put(_roof_layers[k], at, _mask(around, k), true)
	for cell: Vector2i in wall_cells:
		if EcsTownGrid.in_bounds(grid, cell):
			_draw_wall(grid, cell)
	for cell: Vector2i in object_cells:
		_draw_objects(grid, cell)

## Draw order of the four cells around render tile `at`, TL, TR, BL, BR; -1 for none, and off the map.
func _around(grid: EcsTownGridSingleton, at: Vector2i, cells: PackedInt32Array, rank: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(4)
	for q in 4:
		var cell: Vector2i = at + EcsDualGrid.CORNERS[q]
		if not EcsTownGrid.in_bounds(grid, cell):
			out[q] = -1
			continue
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
		if _wall_layer.get_cell_source_id(cell) != -1:
			_wall_layer.erase_cell(cell)
		_draw_door(grid, cell, i)
		return
	if _door_layer.get_cell_source_id(cell) != -1:
		_door_layer.erase_cell(cell)
		redrawn += 1
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
		_door_layer.erase_cell(cell)
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
		_door_layer.set_cell(cell, def.open_source_id, def.open_horizontal if horizontal else def.open_vertical)
	else:
		_door_layer.set_cell(cell, def.closed_source_id, def.closed_horizontal if horizontal else def.closed_vertical)
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
	if tile == null or tile.texture == null:
		if layer.get_cell_source_id(cell) != -1:
			layer.erase_cell(cell)
			redrawn += 1
		return
	var source := _source_for(layer, tile)
	var place := _world.get_component(id, EcsGridPositionComponent) as EcsGridPositionComponent
	if place == null:
		layer.set_cell(cell, source, tile.atlas)
	else:
		# A turned piece draws, on each cell, the slice that turned there, turned the same.
		var offset := EcsTownGrid.turn(cell - place.cell, place.size, 4 - place.turns)
		layer.set_cell(cell, source, tile.atlas + offset, TURN_FLAGS[posmod(place.turns, 4)])
	redrawn += 1
