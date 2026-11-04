class_name EcsRoomDetectionSystem
extends EcsSystem

## The only writer of `room_id` and a building's `rooms`. For each building whose walls or
## doors changed, clears its rooms and flood-fills its footprint, 4-connected, walls and
## doors as boundaries: a fill that leaves the footprint is open and not kept; an enclosed
## one with a door on its boundary is a room; without one it is sealed. The whole building
## is recomputed on every change.

## Buildings recomputed on the last run that had any, and the microseconds it took.
var recomputed: int = 0
var last_usec: int = 0

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
			_detect(grid, building)
			grid.dirty_roofs[id] = true
			recomputed += 1
	grid.dirty_buildings.clear()
	grid.building_revision += 1
	last_usec = Time.get_ticks_usec() - started

func _detect(grid: EcsTownGridSingleton, building: EcsBuildingComponent) -> void:
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
			rooms.append({"id": room_id, "cells": region["cells"], "door_cells": region["door_cells"],
				"sealed": sealed, "type": &""})
	building.rooms = rooms

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
