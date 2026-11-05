class_name EcsBuildingCheck
extends RefCounted

## Pure: whether a built building is sound, read off the grid and room detection, changing
## nothing. Every room has a door, every room and door can be walked to from the entrance,
## and no furniture stands on a door's inside neighbour.

## What is wrong with building `building_id`, entered at door `entrance`; empty when sound.
static func problems(world: EcsWorld, grid: EcsTownGridSingleton, building_id: int, entrance: Vector2i) -> Array[String]:
	var out: Array[String] = []
	var building := world.get_component(building_id, EcsBuildingComponent) as EcsBuildingComponent \
		if building_id > EcsWorld.NO_ENTITY else null
	if building == null:
		return ["no building"]
	var rect := building.footprint
	if not rect.has_point(entrance) or grid.structure[EcsTownGrid.index(grid, entrance)] != EcsTownGridSingleton.DOOR:
		return ["no entrance"]
	var reached := _walk(grid, rect, entrance)
	for room: Dictionary in building.rooms:
		var where: Vector2i = (room["cells"] as Array)[0]
		if room["sealed"]:
			out.append("sealed area at %s" % where)
			continue
		var any := false
		for cell: Vector2i in room["cells"]:
			if reached.has(cell):
				any = true
				break
		if not any:
			out.append("room at %s not reachable" % where)
	for cell in EcsBuildRules.cells(rect):
		var i := EcsTownGrid.index(grid, cell)
		if grid.structure[i] != EcsTownGridSingleton.DOOR:
			continue
		if not reached.has(cell):
			out.append("door at %s not reachable" % cell)
		for side: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next := cell + side
			if not rect.has_point(next):
				continue
			var n := EcsTownGrid.index(grid, next)
			if grid.structure[n] == EcsTownGridSingleton.NONE and grid.object_id[n] != EcsTownGridSingleton.NO_ID:
				out.append("furniture blocks the door at %s" % cell)
	return out

## Cells walkable from `start` inside `rect`: doors, and cells with no wall and no object.
static func _walk(grid: EcsTownGridSingleton, rect: Rect2i, start: Vector2i) -> Dictionary:
	var seen: Dictionary = {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for side: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next := cell + side
			if seen.has(next) or not rect.has_point(next):
				continue
			var i := EcsTownGrid.index(grid, next)
			var open := grid.structure[i] == EcsTownGridSingleton.DOOR \
				or (grid.structure[i] == EcsTownGridSingleton.NONE and grid.object_id[i] == EcsTownGridSingleton.NO_ID)
			if open:
				seen[next] = true
				queue.append(next)
	return seen
