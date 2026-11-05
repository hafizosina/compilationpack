class_name EcsBuildRules
extends RefCounted

## Whether a build command would be accepted, changing nothing: every check the build
## system makes, shared with the tools' placement preview so the two can't disagree.
## `refusal()` returns &"" when it would be accepted, else why not.

static func refusal(world: EcsWorld, grid: EcsTownGridSingleton, catalog: EcsTownCatalog,
		entities: EcsEntityCatalog, command: EcsBuildCommand) -> StringName:
	match command.kind:
		EcsBuildCommand.Kind.CREATE_BUILDING:
			var rect := command.rect
			if not rect.has_area() or not Rect2i(0, 0, grid.width, grid.height).encloses(rect):
				return &"out_of_bounds"
			for cell in cells(rect):
				if grid.building_id[EcsTownGrid.index(grid, cell)] != EcsTownGridSingleton.NO_ID:
					return &"overlaps"
			return &""
		EcsBuildCommand.Kind.CLOSE_BUILDING:
			if command.building <= EcsWorld.NO_ENTITY or not world.has(command.building, EcsBuildingComponent):
				return &"no_building"
			return &""
		EcsBuildCommand.Kind.PLACE_OBJECT:
			return _object_refusal(world, grid, entities, command)
	if not EcsTownGrid.in_bounds(grid, command.cell):
		return &"out_of_bounds"
	var i := EcsTownGrid.index(grid, command.cell)
	match command.kind:
		EcsBuildCommand.Kind.SET_TERRAIN:
			if catalog.terrain(command.value) == null:
				return &"unknown_terrain"
		EcsBuildCommand.Kind.SET_FLOOR:
			if catalog.floor_def(command.value) == null:
				return &"unknown_floor"
			if is_plant(world, grid, entities, grid.object_id[i]):
				return &"plant_here"
		EcsBuildCommand.Kind.PLACE_WALL:
			if catalog.wall(command.value) == null:
				return &"unknown_wall"
			if grid.building_id[i] == EcsTownGridSingleton.NO_ID:
				return &"outside_building"
			if command.building != EcsTownGridSingleton.NO_ID and command.building != grid.building_id[i]:
				return &"not_its_building"
			if grid.object_id[i] != EcsTownGridSingleton.NO_ID:
				return &"occupied"
		EcsBuildCommand.Kind.PLACE_DOOR:
			if catalog.door(command.value) == null:
				return &"unknown_door"
			if grid.structure[i] != EcsTownGridSingleton.WALL:
				return &"not_on_wall"
			if command.building != EcsTownGridSingleton.NO_ID and command.building != grid.building_id[i]:
				return &"not_its_building"
			if door_runs_across(grid, command.cell) == door_runs_down(grid, command.cell):
				return &"not_a_straight_wall"
		EcsBuildCommand.Kind.TOGGLE_DOOR:
			if grid.structure[i] != EcsTownGridSingleton.DOOR:
				return &"not_a_door"
			if grid.object_id[i] <= EcsWorld.NO_ENTITY or not world.has(grid.object_id[i], EcsDoorComponent):
				return &"not_built_yet"
		EcsBuildCommand.Kind.REMOVE_OBJECT:
			if grid.object_id[i] == EcsTownGridSingleton.NO_ID or grid.structure[i] != EcsTownGridSingleton.NONE:
				return &"nothing_here"
		EcsBuildCommand.Kind.ATTACH:
			var attachable := template(entities, command.blueprint, &"attachable") as EcsAttachableComponent
			if attachable == null:
				return &"unknown_attachment"
			if grid.attachment_id[i] != EcsTownGridSingleton.NO_ID:
				return &"slot_taken"
			if grid.structure[i] == EcsTownGridSingleton.WALL:
				if not attachable.on_wall:
					return &"not_for_this_host"
			elif grid.structure[i] == EcsTownGridSingleton.NONE and grid.object_id[i] != EcsTownGridSingleton.NO_ID:
				if not holds(world, grid, entities, grid.object_id[i]):
					return &"no_host"
				if not attachable.on_furniture:
					return &"not_for_this_host"
			else:
				return &"no_host"
		EcsBuildCommand.Kind.DETACH:
			if grid.attachment_id[i] == EcsTownGridSingleton.NO_ID:
				return &"nothing_here"
	return &""

## Furniture or a plant: every covered cell free of walls, doors and objects, all in one
## building or none, a plant on no floor.
static func _object_refusal(world: EcsWorld, grid: EcsTownGridSingleton, entities: EcsEntityCatalog,
		command: EcsBuildCommand) -> StringName:
	var place := template(entities, command.blueprint, &"grid_position") as EcsGridPositionComponent
	if place == null or template(entities, command.blueprint, &"tile") == null:
		return &"unknown_object"
	var rect := Rect2i(command.cell, EcsTownGrid.turned(place.size, command.value))
	if not Rect2i(0, 0, grid.width, grid.height).encloses(rect):
		return &"out_of_bounds"
	var plant := template(entities, command.blueprint, &"plant") != null
	var owner := grid.building_id[EcsTownGrid.index(grid, command.cell)]
	for cell in cells(rect):
		var i := EcsTownGrid.index(grid, cell)
		if grid.structure[i] != EcsTownGridSingleton.NONE or grid.object_id[i] != EcsTownGridSingleton.NO_ID:
			return &"occupied"
		if plant and grid.floor[i] != 0:
			return &"plant_on_floor"
		if grid.building_id[i] != owner:
			return &"straddles"
	if command.building != EcsTownGridSingleton.NO_ID and command.building != owner:
		return &"not_its_building"
	return &""

## A door here would lie left-right: its building's wall or door on both sides.
static func door_runs_across(grid: EcsTownGridSingleton, cell: Vector2i) -> bool:
	return joins(grid, cell, Vector2i.LEFT) and joins(grid, cell, Vector2i.RIGHT)

static func door_runs_down(grid: EcsTownGridSingleton, cell: Vector2i) -> bool:
	return joins(grid, cell, Vector2i.UP) and joins(grid, cell, Vector2i.DOWN)

## Whether the cell beside `cell` towards `side` is a wall or door of the same building.
static func joins(grid: EcsTownGridSingleton, cell: Vector2i, side: Vector2i) -> bool:
	var next := cell + side
	if not EcsTownGrid.in_bounds(grid, next):
		return false
	var n := EcsTownGrid.index(grid, next)
	return grid.structure[n] != EcsTownGridSingleton.NONE \
		and grid.building_id[n] == grid.building_id[EcsTownGrid.index(grid, cell)]

## Whether object `id` (born or reserved) is furniture that holds attachments.
static func holds(world: EcsWorld, grid: EcsTownGridSingleton, entities: EcsEntityCatalog, id: int) -> bool:
	if id > EcsWorld.NO_ENTITY:
		var furniture := world.get_component(id, EcsFurnitureComponent) as EcsFurnitureComponent
		return furniture != null and furniture.holds
	if grid.pending.has(id):
		var furniture := template(entities, (grid.pending[id] as EcsSpawnRequest).type_id, &"furniture") as EcsFurnitureComponent
		return furniture != null and furniture.holds
	return false

static func is_plant(world: EcsWorld, grid: EcsTownGridSingleton, entities: EcsEntityCatalog, id: int) -> bool:
	if id > EcsWorld.NO_ENTITY:
		return world.has(id, EcsPlantComponent)
	if grid.pending.has(id):
		return template(entities, (grid.pending[id] as EcsSpawnRequest).type_id, &"plant") != null
	return false

static func template(entities: EcsEntityCatalog, blueprint: StringName, component_key: StringName) -> EcsComponent:
	if entities == null or blueprint == &"" or not entities.has_def(blueprint):
		return null
	return entities.get_def(blueprint).template(component_key)

static func cells(rect: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			out.append(Vector2i(x, y))
	return out
