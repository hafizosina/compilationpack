class_name EcsTownCatalog
extends Resource

## Every tile type the town can draw, each from its own sheet; the TileSets are made from
## the sheets at start, never stored. Each def is named by its `key`; the catalog numbers
## each list 1, 2, 3, ... in order for the grid, so nothing is numbered by hand. Anything
## kept — a save, a building def — stores keys, never these numbers.

@export var terrains: Array[EcsTerrainDef] = []
@export var floors: Array[EcsFloorDef] = []
@export var walls: Array[EcsWallDef] = []
@export var doors: Array[EcsDoorDef] = []
@export var roofs: Array[EcsRoofDef] = []
@export var room_types: Array[EcsRoomTypeDef] = []
## Kinds of building the generator makes.
@export var building_types: Array[EcsBuildingTypeDef] = []

var _numbered: bool = false
## Dual-grid TileSets made from defs' sheets this run: def -> TileSet.
var _tile_sets: Dictionary = {}
var _wall_tile_set: TileSet
## Every terrain's ground, one layer each in list order, made the first time it is asked for.
var _grounds: Texture2DArray
## Pixels a side of a ground texture: 8 cells at EcsTownGrid.ART.
const GROUND_SIZE: int = 512

## Numbers every def by its place in its list, once, and gives walls and doors their sources
## in the walls' TileSet; warns on a key used twice in a list.
func number() -> void:
	if _numbered:
		return
	_numbered = true
	for list: Array in [terrains, floors, walls, doors, roofs]:
		var seen: Dictionary = {}
		for k in list.size():
			list[k].id = k + 1
			if seen.has(list[k].key):
				push_warning("EcsTownCatalog: key '%s' is used twice in one list" % list[k].key)
			seen[list[k].key] = true
	wall_tiles()

## The TileSet of a terrain, floor or roof def, made from its sheet the first time it is asked for.
func tiles(def: EcsTileDef) -> TileSet:
	if def.texture == null:
		return null
	if not _tile_sets.has(def):
		_tile_sets[def] = EcsDualGrid.make_tile_set(def.texture, def.tile_size)
	return _tile_sets[def]

## The terrains' grounds as one array, a layer per terrain in list order, each GROUND_SIZE square;
## a terrain with no `ground` repeats its sheet's full tile.
func grounds() -> Texture2DArray:
	if _grounds != null:
		return _grounds
	var images: Array[Image] = []
	for def in terrains:
		var image: Image
		if def.ground != null:
			image = def.ground.get_image()
			if image.is_compressed():
				image.decompress()
			image.convert(Image.FORMAT_RGBA8)
			image.resize(GROUND_SIZE, GROUND_SIZE, Image.INTERPOLATE_LANCZOS)
		else:
			image = _repeat_full_tile(def)
		image.generate_mipmaps()
		images.append(image)
	_grounds = Texture2DArray.new()
	_grounds.create_from_images(images)
	return _grounds

func _repeat_full_tile(def: EcsTerrainDef) -> Image:
	var image := Image.create_empty(GROUND_SIZE, GROUND_SIZE, false, Image.FORMAT_RGBA8)
	var set := tiles(def)
	if set == null:
		return image
	var source := set.get_source(set.get_source_id(0)) as TileSetAtlasSource
	var sheet := source.texture.get_image()
	if sheet.is_compressed():
		sheet.decompress()
	sheet.convert(Image.FORMAT_RGBA8)
	var full: Vector2i = (EcsDualGrid.corner_layout(source)[EcsDualGrid.FULL] as Array)[0]
	var tile := sheet.get_region(source.get_tile_texture_region(full))
	tile.resize(EcsTownGrid.ART, EcsTownGrid.ART, Image.INTERPOLATE_NEAREST)
	for y in range(0, GROUND_SIZE, EcsTownGrid.ART):
		for x in range(0, GROUND_SIZE, EcsTownGrid.ART):
			image.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i(x, y))
	return image

## Walls and doors in one TileSet on the cell grid, made once, when the catalog numbers its
## defs: a source per wall sheet and per door sheet (one for a sheet two doors share), whose
## ids it writes on the defs.
func wall_tiles() -> TileSet:
	if _wall_tile_set != null:
		return _wall_tile_set
	_wall_tile_set = TileSet.new()
	_wall_tile_set.tile_size = Vector2i(EcsTownGrid.ART, EcsTownGrid.ART)
	var made: Dictionary = {}
	var add := func(texture: Texture2D, size: int, margins: Vector2i, scale: float) -> int:
		if texture == null:
			return -1
		var key := [texture, size, margins]
		if not made.has(key):
			made[key] = _wall_tile_set.add_source(EcsDualGrid.make_source(texture, size, margins, scale))
		return made[key]
	for def in walls:
		def.source_id = add.call(def.texture, def.tile_size, Vector2i.ZERO, float(EcsTownGrid.ART) / def.tile_size)
	for def in doors:
		var scale := float(EcsTownGrid.ART) / def.cell_pixels
		def.closed_source_id = add.call(def.closed_texture, def.tile_size, def.closed_margins, scale)
		def.open_source_id = add.call(def.open_texture, def.tile_size, def.open_margins, scale)
	return _wall_tile_set

## The room type with id `key`, or null.
func room_type(key: StringName) -> EcsRoomTypeDef:
	for def in room_types:
		if def.id == key:
			return def
	return null

func terrain(id: int) -> EcsTerrainDef:
	return _by_id(terrains, id)

func floor_def(id: int) -> EcsFloorDef:
	return _by_id(floors, id)

func wall(id: int) -> EcsWallDef:
	return _by_id(walls, id)

func door(id: int) -> EcsDoorDef:
	return _by_id(doors, id)

## The grid number of the def named `key`, or 0 when there is none.
func terrain_id(key: StringName) -> int:
	return _id_of(terrains, key)

func floor_id(key: StringName) -> int:
	return _id_of(floors, key)

func wall_id(key: StringName) -> int:
	return _id_of(walls, key)

func door_id(key: StringName) -> int:
	return _id_of(doors, key)

func roof_id(key: StringName) -> int:
	return _id_of(roofs, key)

func _by_id(list: Array, id: int) -> Variant:
	number()
	return list[id - 1] if id >= 1 and id <= list.size() else null

func _id_of(list: Array, key: StringName) -> int:
	number()
	for def in list:
		if def.key == key:
			return def.id
	return 0
