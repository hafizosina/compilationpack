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

var _numbered: bool = false
## Dual-grid TileSets made from defs' sheets this run: def -> TileSet.
var _tile_sets: Dictionary = {}
var _wall_tile_set: TileSet

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

## Walls and doors in one TileSet on the cell grid, made once, when the catalog numbers its
## defs: a source per wall sheet and per door sheet (one for a sheet two doors share), whose
## ids it writes on the defs.
func wall_tiles() -> TileSet:
	if _wall_tile_set != null:
		return _wall_tile_set
	_wall_tile_set = TileSet.new()
	_wall_tile_set.tile_size = Vector2i(EcsTownGrid.CELL, EcsTownGrid.CELL)
	var made: Dictionary = {}
	var add := func(texture: Texture2D, size: int, margins: Vector2i) -> int:
		if texture == null:
			return -1
		var key := [texture, size, margins]
		if not made.has(key):
			made[key] = _wall_tile_set.add_source(EcsDualGrid.make_source(texture, size, margins))
		return made[key]
	for def in walls:
		def.source_id = add.call(def.texture, def.tile_size, Vector2i.ZERO)
	for def in doors:
		def.closed_source_id = add.call(def.closed_texture, def.tile_size, def.closed_margins)
		def.open_source_id = add.call(def.open_texture, def.tile_size, def.open_margins)
	return _wall_tile_set

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
