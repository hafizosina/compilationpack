class_name EcsTownCatalog
extends Resource

## Every tile type the town can draw. Each def is named by its `key`; the catalog numbers
## each list 1, 2, 3, ... in order for the grid, so nothing is numbered by hand. Anything
## kept — a save, a building def — stores keys, never these numbers.

@export var terrains: Array[EcsTerrainDef] = []
@export var floors: Array[EcsFloorDef] = []
@export var walls: Array[EcsWallDef] = []
@export var doors: Array[EcsDoorDef] = []
@export var roofs: Array[EcsRoofDef] = []
@export var room_types: Array[EcsRoomTypeDef] = []
## Name of the TileMapLayer that draws walls and doors, on the cell grid.
@export var wall_layer: StringName = &"ObjectLayer"
## TileMapLayers for furniture and plants, and for attachments, both on the cell grid.
@export var furniture_layer: StringName = &"FurnitureLayer"
@export var attachment_layer: StringName = &"AttachmentLayer"

var _numbered: bool = false

## Numbers every def by its place in its list, once; warns on a key used twice in a list.
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
