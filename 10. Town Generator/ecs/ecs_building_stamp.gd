class_name EcsBuildingStamp
extends RefCounted

## Pure: captures a building from the grid as an EcsBuildingDef, and turns a def back into
## the build commands the player's tools send, rotated in quarter turns clockwise.

## The building with id `building_id` as a def, read off the grid; null if it is no building.
static func capture(world: EcsWorld, grid: EcsTownGridSingleton, catalog: EcsTownCatalog,
		building_id: int, key: StringName = &"") -> EcsBuildingDef:
	var building := world.get_component(building_id, EcsBuildingComponent) as EcsBuildingComponent \
		if building_id > EcsWorld.NO_ENTITY else null
	if building == null:
		return null
	var rect := building.footprint
	var def := EcsBuildingDef.new()
	def.key = key
	def.display_name = String(key).capitalize()
	def.size = rect.size
	def.closed = building.closed
	for cell in EcsBuildRules.cells(rect):
		var i := EcsTownGrid.index(grid, cell)
		var at := cell - rect.position
		if grid.floor[i] != 0:
			def.floors[at] = catalog.floor_def(grid.floor[i]).key
		if grid.structure[i] == EcsTownGridSingleton.WALL:
			def.walls[at] = catalog.wall(grid.wall_type[i]).key
		elif grid.structure[i] == EcsTownGridSingleton.DOOR:
			def.doors[at] = catalog.door(grid.wall_type[i]).key
		elif grid.object_id[i] != EcsTownGridSingleton.NO_ID:
			var place := place_of(world, grid, grid.object_id[i])
			if place.position == cell:
				def.objects[at] = blueprint_of(world, grid, grid.object_id[i])
				var turns := turns_of(world, grid, grid.object_id[i])
				if turns != 0:
					def.object_turns[at] = turns
		if grid.attachment_id[i] != EcsTownGridSingleton.NO_ID:
			def.attachments[at] = blueprint_of(world, grid, grid.attachment_id[i])
	return def

## The footprint `def` covers when turned `turns` quarter turns.
static func turned_size(def: EcsBuildingDef, turns: int) -> Vector2i:
	return EcsTownGrid.turned(def.size, turns)

## Commands that build `def` with its top-left at `at`, turned `turns` quarter turns clockwise:
## the building, floors, walls (a wall under each door, which the door then replaces),
## doors, pieces (each turned with the building), then attachments.
static func commands(def: EcsBuildingDef, catalog: EcsTownCatalog, entities: EcsEntityCatalog,
		at: Vector2i, turns: int = 0) -> Array[EcsBuildCommand]:
	turns = posmod(turns, 4)
	var out: Array[EcsBuildCommand] = [EcsBuildCommand.create_building(Rect2i(at, turned_size(def, turns)), def.closed)]
	for cell: Vector2i in def.floors:
		out.append(EcsBuildCommand.make(EcsBuildCommand.Kind.SET_FLOOR, at + EcsTownGrid.turn(cell, def.size, turns),
			catalog.floor_id(def.floors[cell])))
	for cell: Vector2i in def.walls:
		out.append(EcsBuildCommand.make(EcsBuildCommand.Kind.PLACE_WALL, at + EcsTownGrid.turn(cell, def.size, turns),
			catalog.wall_id(def.walls[cell])))
	for cell: Vector2i in def.doors:
		out.append(EcsBuildCommand.make(EcsBuildCommand.Kind.PLACE_WALL, at + EcsTownGrid.turn(cell, def.size, turns),
			_wall_beside(def, catalog, cell)))
	for cell: Vector2i in def.doors:
		out.append(EcsBuildCommand.make(EcsBuildCommand.Kind.PLACE_DOOR, at + EcsTownGrid.turn(cell, def.size, turns),
			catalog.door_id(def.doors[cell])))
	for cell: Vector2i in def.objects:
		var own: int = def.object_turns.get(cell, 0)
		var covers := EcsTownGrid.turned(_piece_size(entities, def.objects[cell]), own)
		var to := EcsTownGrid.turn_rect(Rect2i(cell, covers), def.size, turns).position
		out.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, at + to, def.objects[cell], (own + turns) % 4))
	for cell: Vector2i in def.attachments:
		out.append(EcsBuildCommand.place(EcsBuildCommand.Kind.ATTACH, at + EcsTownGrid.turn(cell, def.size, turns),
			def.attachments[cell]))
	return out

## The blueprint an object id (born or reserved) was made from.
static func blueprint_of(world: EcsWorld, grid: EcsTownGridSingleton, id: int) -> StringName:
	if id > EcsWorld.NO_ENTITY:
		var named := world.get_component(id, EcsNameComponent) as EcsNameComponent
		return named.type_id if named != null else &""
	if grid.pending.has(id):
		return (grid.pending[id] as EcsSpawnRequest).type_id
	return &""

## The quarter turns object `id` (born or reserved) was placed with.
static func turns_of(world: EcsWorld, grid: EcsTownGridSingleton, id: int) -> int:
	if id > EcsWorld.NO_ENTITY:
		var place := world.get_component(id, EcsGridPositionComponent) as EcsGridPositionComponent
		return place.turns if place != null else 0
	if grid.pending.has(id):
		return int(((grid.pending[id] as EcsSpawnRequest).overrides.get("grid_position", {}) as Dictionary).get("turns", 0))
	return 0

## The cells object `id` (born or reserved) covers.
static func place_of(world: EcsWorld, grid: EcsTownGridSingleton, id: int) -> Rect2i:
	if id > EcsWorld.NO_ENTITY:
		var place := world.get_component(id, EcsGridPositionComponent) as EcsGridPositionComponent
		return Rect2i(place.cell, place.size) if place != null else Rect2i()
	if grid.pending.has(id):
		var spot: Dictionary = (grid.pending[id] as EcsSpawnRequest).overrides.get("grid_position", {})
		return Rect2i(spot.get("cell", Vector2i.ZERO), spot.get("size", Vector2i.ONE))
	return Rect2i()

static func _piece_size(entities: EcsEntityCatalog, blueprint: StringName) -> Vector2i:
	var place := EcsBuildRules.template(entities, blueprint, &"grid_position") as EcsGridPositionComponent
	return place.size if place != null else Vector2i.ONE

## A door stands in a wall; the wall under it is the type of a wall beside it.
static func _wall_beside(def: EcsBuildingDef, catalog: EcsTownCatalog, cell: Vector2i) -> int:
	for side: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if def.walls.has(cell + side):
			return catalog.wall_id(def.walls[cell + side])
	return 1
