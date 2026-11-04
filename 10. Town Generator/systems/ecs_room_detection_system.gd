class_name EcsRoomDetectionSystem
extends EcsSystem

## The only writer of `room_id` and a building's `rooms`. For each building whose walls or
## doors changed, clears its rooms and flood-fills its footprint, 4-connected, walls and
## doors as boundaries: a fill that leaves the footprint is open and not kept; an enclosed
## one with a door on its boundary is a room; without one it is sealed. The whole building
## is recomputed on every change. A room's type comes from its furniture: the highest-priority
## room type any of its furniture's tags satisfies.

var _catalog: EcsTownCatalog

## Buildings recomputed on the last run that had any, and the microseconds it took.
var recomputed: int = 0
var last_usec: int = 0

func _init(catalog: EcsTownCatalog = null) -> void:
	_catalog = catalog

func label() -> StringName:
	return &"rooms"

func run(world: EcsWorld, _delta: float) -> void:
	var grid := world.get_singleton(EcsTownGridSingleton) as EcsTownGridSingleton
	if grid == null or grid.dirty_buildings.is_empty():
		return
	var started := Time.get_ticks_usec()
	recomputed = 0
	for id: int in grid.dirty_buildings:
		var building := world.get_component(id, EcsBuildingComponent) as EcsBuildingComponent
		if building != null:
			_detect(world, grid, building)
			grid.dirty_roofs[id] = true
			recomputed += 1
	grid.dirty_buildings.clear()
	grid.building_revision += 1
	last_usec = Time.get_ticks_usec() - started

func _detect(world: EcsWorld, grid: EcsTownGridSingleton, building: EcsBuildingComponent) -> void:
	var rect := building.footprint
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			grid.room_id[y * grid.width + x] = EcsTownGridSingleton.NO_ID
	var seen := PackedByteArray()
	seen.resize(rect.size.x * rect.size.y)
	var rooms: Array = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var local := (y - rect.position.y) * rect.size.x + (x - rect.position.x)
			if seen[local] or grid.structure[y * grid.width + x] != EcsTownGridSingleton.NONE:
				continue
			var region := _fill(grid, rect, Vector2i(x, y), seen)
			if region.is_empty():
				continue
			var sealed: bool = (region["door_cells"] as Array).is_empty()
			var room_id := EcsTownGridSingleton.NO_ID
			if not sealed:
				room_id = grid.next_room_id
				grid.next_room_id += 1
				for cell: Vector2i in region["cells"]:
					grid.room_id[EcsTownGrid.index(grid, cell)] = room_id
			var type := _type_of(world, grid, region["cells"]) if not sealed else null
			rooms.append({"id": room_id, "cells": region["cells"], "door_cells": region["door_cells"],
				"sealed": sealed, "type": type.id if type != null else &"",
				"label": type.display_name if type != null else ""})
	building.rooms = rooms

## The best room type the furniture in `cells` satisfies, or null.
func _type_of(world: EcsWorld, grid: EcsTownGridSingleton, cells: Array) -> EcsRoomTypeDef:
	if _catalog == null:
		return null
	var tags: Dictionary = {}
	var seen: Dictionary = {}
	for cell: Vector2i in cells:
		var id := grid.object_id[EcsTownGrid.index(grid, cell)]
		if id <= EcsWorld.NO_ENTITY or seen.has(id):
			continue
		seen[id] = true
		var furniture := world.get_component(id, EcsFurnitureComponent) as EcsFurnitureComponent
		if furniture != null:
			for tag in furniture.tags:
				tags[tag] = true
	var best: EcsRoomTypeDef = null
	for type in _catalog.room_types:
		if best != null and type.priority <= best.priority:
			continue
		for need in type.needs:
			if tags.has(need):
				best = type
				break
	return best

## The 4-connected open cells from `start`, and the doors on their boundary; empty if the
## fill leaves the footprint.
func _fill(grid: EcsTownGridSingleton, rect: Rect2i, start: Vector2i, seen: PackedByteArray) -> Dictionary:
	var cells: Array[Vector2i] = [start]
	var doors: Dictionary = {}
	var leaks := false
	seen[(start.y - rect.position.y) * rect.size.x + (start.x - rect.position.x)] = 1
	var k := 0
	while k < cells.size():
		var cell := cells[k]
		k += 1
		for side in EcsDualGrid.SIDES:
			var next: Vector2i = cell + side
			if not rect.has_point(next):
				leaks = true
				continue
			var structure := grid.structure[EcsTownGrid.index(grid, next)]
			if structure == EcsTownGridSingleton.DOOR:
				doors[next] = true
			elif structure == EcsTownGridSingleton.NONE:
				var local := (next.y - rect.position.y) * rect.size.x + (next.x - rect.position.x)
				if not seen[local]:
					seen[local] = 1
					cells.append(next)
	if leaks:
		return {}
	var door_cells: Array[Vector2i] = []
	for door: Vector2i in doors:
		door_cells.append(door)
	return {"cells": cells, "door_cells": door_cells}
