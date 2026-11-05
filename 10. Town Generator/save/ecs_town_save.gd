class_name EcsTownSave
extends Resource

## A saved town, every type by key: its ground, what lies outside buildings, and each
## building as an EcsBuildingDef. Loading is the build commands that make it again.

const SAVE_DIR := "user://towns/"

## Grid size in cells.
@export var size: Vector2i = Vector2i.ZERO
## Terrain keys used; `terrain` holds an index into this per cell.
@export var terrain_keys: Array[StringName] = []
@export var terrain: PackedInt32Array = PackedInt32Array()
## Outside any building: floor cell -> floor key, piece top-left -> blueprint, slot -> blueprint.
@export var floors: Dictionary[Vector2i, StringName] = {}
@export var objects: Dictionary[Vector2i, StringName] = {}
## A turned piece outside buildings: top-left -> quarter turns clockwise.
@export var object_turns: Dictionary[Vector2i, int] = {}
@export var attachments: Dictionary[Vector2i, StringName] = {}
## Every building, and the grid cell of its top-left.
@export var buildings: Array[EcsBuildingDef] = []
@export var building_at: Array[Vector2i] = []

## The town on `grid` as data. Only reads.
static func capture(world: EcsWorld, grid: EcsTownGridSingleton, catalog: EcsTownCatalog) -> EcsTownSave:
	var save := EcsTownSave.new()
	save.size = Vector2i(grid.width, grid.height)
	save.terrain.resize(grid.width * grid.height)
	var palette: Dictionary = {}
	var seen: Dictionary = {}
	for i in grid.width * grid.height:
		var cell := Vector2i(i % grid.width, i / grid.width)
		var key := catalog.terrain(grid.terrain[i]).key
		if not palette.has(key):
			palette[key] = save.terrain_keys.size()
			save.terrain_keys.append(key)
		save.terrain[i] = palette[key]
		var building := grid.building_id[i]
		if building != EcsTownGridSingleton.NO_ID:
			if building > EcsWorld.NO_ENTITY and not seen.has(building):
				seen[building] = true
				var def := EcsBuildingStamp.capture(world, grid, catalog, building, &"building_%d" % save.buildings.size())
				save.buildings.append(def)
				save.building_at.append((world.get_component(building, EcsBuildingComponent) as EcsBuildingComponent).footprint.position)
			continue
		if grid.floor[i] != 0:
			save.floors[cell] = catalog.floor_def(grid.floor[i]).key
		var object := grid.object_id[i]
		if object != EcsTownGridSingleton.NO_ID and EcsBuildingStamp.place_of(world, grid, object).position == cell:
			save.objects[cell] = EcsBuildingStamp.blueprint_of(world, grid, object)
			var turns := EcsBuildingStamp.turns_of(world, grid, object)
			if turns != 0:
				save.object_turns[cell] = turns
		if grid.attachment_id[i] != EcsTownGridSingleton.NO_ID:
			save.attachments[cell] = EcsBuildingStamp.blueprint_of(world, grid, grid.attachment_id[i])
	return save

## The commands that build the saved town on an empty grid of `base_terrain`: ground, floors,
## buildings, then what stands outside them.
func commands(catalog: EcsTownCatalog, entities: EcsEntityCatalog, base_terrain: int) -> Array[EcsBuildCommand]:
	var out: Array[EcsBuildCommand] = []
	var ids: Array[int] = []
	for key in terrain_keys:
		ids.append(catalog.terrain_id(key))
	for i in terrain.size():
		if ids[terrain[i]] != base_terrain:
			out.append(EcsBuildCommand.make(EcsBuildCommand.Kind.SET_TERRAIN, Vector2i(i % size.x, i / size.x), ids[terrain[i]]))
	for cell: Vector2i in floors:
		out.append(EcsBuildCommand.make(EcsBuildCommand.Kind.SET_FLOOR, cell, catalog.floor_id(floors[cell])))
	for k in buildings.size():
		out.append_array(EcsBuildingStamp.commands(buildings[k], catalog, entities, building_at[k]))
	for cell: Vector2i in objects:
		out.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, cell, objects[cell], object_turns.get(cell, 0)))
	for cell: Vector2i in attachments:
		out.append(EcsBuildCommand.place(EcsBuildCommand.Kind.ATTACH, cell, attachments[cell]))
	return out
