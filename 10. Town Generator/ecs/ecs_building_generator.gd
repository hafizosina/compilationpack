class_name EcsBuildingGenerator
extends RefCounted

## Pure and seeded: lays out a building of a type, wealth and size and gives back the build
## commands the player's tools send, so everything downstream is the tested path. The same
## inputs always give the same commands.
##   0. Grow (a type laid out by &"grow"): the main room on the front, at the door; each next
##      room, sized by its room type, attached to a wall of one already placed, front, back or side
##      as its type says, inside the footprint, never closing in a pocket of open ground. Each
##      room is its own walled part. One that fits nowhere is left out; when the main room can't
##      stand, the building is split instead.
##   0. Shape: with more than one room, by the type's `shapes`, the footprint's back is cut into
##      an L, a T (a wing) or a U; the front stays whole. Each part is walled, and the cut is open
##      ground inside the footprint, which room detection and roofs already leave out.
##   1. Rooms: each part, then the largest room, split by binary space partition, never below the
##      type's smallest room.
##   2. Walls: every part's perimeter and the splits.
##   3. Doors: the entrance on the facing side, at `door` when that can be one; inner doors along
##      a spanning tree of the rooms, so every room is reachable, and by chance one more, making a loop.
##   4. Roles from the type's list, largest room first.
##   5. Floor by wealth; the poorest has none.
##   6. Furniture by role, turned to fit, against a wall or free-standing, never on a door's
##      inside neighbour and never cutting a room in two; a piece its room type places (`layout`)
##      goes where it says in the frame of the room's main door (back wall, side, back corner,
##      beside the door, middle), keeping the way in from the door clear.

## The commands for a building of `type` with its top-left at `at`; `door`, a cell at `at` on the
## facing side, is the entrance when it can be.
static func generate(type: EcsBuildingTypeDef, size: Vector2i, wealth: int, facing: Vector2i,
		rng_seed: int, catalog: EcsTownCatalog, entities: EcsEntityCatalog, at: Vector2i = Vector2i.ZERO,
		door: Vector2i = Vector2i(-1, -1)) -> Array[EcsBuildCommand]:
	return plan(type, size, wealth, facing, rng_seed, catalog, entities, at, door)["commands"]

## The layout behind `generate`, for checks and viewers: {commands, shape, cells (the walled
## shape's cells), rooms: [{rect, role}], entrance, doors, missing: [blueprints that found no
## place]}, all cells at `at`.
static func plan(type: EcsBuildingTypeDef, size: Vector2i, wealth: int, facing: Vector2i,
		rng_seed: int, catalog: EcsTownCatalog, entities: EcsEntityCatalog, at: Vector2i = Vector2i.ZERO,
		door: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var grown := _grow(type, size, wealth, facing, rng, catalog, door - at if door != Vector2i(-1, -1) else door) \
		if type.layout == &"grow" else {}
	var shaped := grown if not grown.is_empty() else _shape(type, size, wealth, facing, rng)
	var parts: Array[Rect2i] = shaped["parts"]
	var walls: Dictionary = {}
	var cells: Array[Vector2i] = []
	var inside: Array[Rect2i] = []
	for part in parts:
		inside.append(part.grow(-1))
		for y in range(part.position.y, part.end.y):
			for x in range(part.position.x, part.end.x):
				if x == part.position.x or y == part.position.y or x == part.end.x - 1 or y == part.end.y - 1:
					walls[Vector2i(x, y)] = true
	var in_shape: Dictionary = {}
	for part in parts:
		for cell in EcsBuildRules.cells(part):
			if not in_shape.has(cell):
				in_shape[cell] = true
				cells.append(at + cell)
	var rooms: Array[Rect2i] = inside if not grown.is_empty() else _split(inside, type, wealth, rng, walls)
	var room_of := _room_map(rooms)
	var entrance := _entrance(size, facing, room_of, walls, rng, door - at if door != Vector2i(-1, -1) else door)
	var doors: Array[Vector2i] = []
	if entrance != Vector2i(-1, -1):
		doors.append(entrance)
		doors.append_array(_inner_doors(rooms, room_of, walls, room_of[entrance - facing], type, rng))
	var roles: Array[StringName] = grown["roles"] if not grown.is_empty() else _roles(rooms, type)
	var out: Array[EcsBuildCommand] = [EcsBuildCommand.create_building(Rect2i(at, size))]
	var wall_id := catalog.wall_id(EcsBuildingTypeDef.by_wealth(type.walls, wealth))
	for cell: Vector2i in walls:
		out.append(EcsBuildCommand.make(EcsBuildCommand.Kind.PLACE_WALL, at + cell, wall_id))
	var door_id := catalog.door_id(EcsBuildingTypeDef.by_wealth(type.doors, wealth))
	for cell in doors:
		out.append(EcsBuildCommand.make(EcsBuildCommand.Kind.PLACE_DOOR, at + cell, door_id))
	var floor_id := catalog.floor_id(EcsBuildingTypeDef.by_wealth(type.floors, wealth))
	if floor_id != 0:
		for room in rooms:
			for cell in EcsBuildRules.cells(room):
				out.append(EcsBuildCommand.make(EcsBuildCommand.Kind.SET_FLOOR, at + cell, floor_id))
	var missing: Array[StringName] = []
	var chance: float = EcsBuildingTypeDef.by_wealth(type.optional_chance, wealth)
	for k in rooms.size():
		var role := catalog.room_type(roles[k])
		if role == null:
			continue
		var pieces: Array[StringName] = role.required.duplicate()
		for blueprint in role.optional:
			if rng.randf() < chance:
				pieces.append(blueprint)
		for placed in _furnish(rooms[k], pieces, doors, entities, rng, missing, role.layout):
			out.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, at + placed[0], placed[1], placed[2]))
	var listed: Array = []
	for k in rooms.size():
		listed.append({"rect": Rect2i(at + rooms[k].position, rooms[k].size), "role": roles[k]})
	var placed_doors: Array[Vector2i] = []
	for cell in doors:
		placed_doors.append(at + cell)
	return {"commands": out, "shape": shaped["shape"], "cells": cells, "rooms": listed,
		"entrance": at + entrance if entrance != Vector2i(-1, -1) else entrance, "doors": placed_doors, "missing": missing}

## A grown building: {shape: &"grown", parts (each one walled room), roles}; empty when its main
## room can't stand. Worked in the facing frame (u along the front, v back from it).
static func _grow(type: EcsBuildingTypeDef, size: Vector2i, wealth: int, facing: Vector2i, rng: RandomNumberGenerator,
		catalog: EcsTownCatalog, door: Vector2i) -> Dictionary:
	var across := size.x if facing.y != 0 else size.y
	var depth := size.y if facing.y != 0 else size.x
	var want: int = mini(EcsBuildingTypeDef.by_wealth(type.rooms, wealth), maxi(type.roles.size(), 1))
	var wanted: Array[StringName] = []
	for k in want:
		wanted.append(type.roles[mini(k, type.roles.size() - 1)] if not type.roles.is_empty() else &"")
	var door_u := -1
	if door != Vector2i(-1, -1):
		for u in across:
			if _frame_cell(Vector2i(u, 0), size, facing) == door:
				door_u = u
	var frame: Array[Rect2i] = []
	var roles: Array[StringName] = []
	# The main room: on the front, over the door.
	var main := catalog.room_type(wanted[0])
	var main_sizes := _outer_sizes(main, type, rng)
	for outer: Vector2i in main_sizes:
		if outer.x > across or outer.y > depth:
			continue
		var lo := 0
		var hi := across - outer.x
		if door_u >= 0:
			lo = clampi(door_u - outer.x + 2, 0, hi)
			hi = clampi(door_u - 1, lo, hi)
		frame.append(Rect2i(rng.randi_range(lo, hi), 0, outer.x, outer.y))
		roles.append(wanted[0])
		break
	if frame.is_empty():
		return {}
	for k in range(1, wanted.size()):
		var room := catalog.room_type(wanted[k])
		var place: StringName = room.place if room != null else &"any"
		var best := Rect2i()
		var best_score := -INF
		for outer: Vector2i in _outer_sizes(room, type, rng):
			for rect in _attachments(frame, outer, place):
				if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > across or rect.end.y > depth:
					continue
				if not _clear_of(rect, frame) or _closes_pocket(rect, frame, Vector2i(across, depth)):
					continue
				var score := _shared(rect, frame) * 0.5 + rng.randf()
				if score > best_score:
					best_score = score
					best = rect
			if best.has_area():
				break
		if best.has_area():
			frame.append(best)
			roles.append(wanted[k])
	var parts: Array[Rect2i] = []
	for rect in frame:
		parts.append(_from_frame(rect, size, facing))
	return {"shape": &"grown", "parts": parts, "roles": roles}

## Outer sizes (walls included) to try for a room of `room`: a random one in its range, its
## smallest, its largest, each also turned.
static func _outer_sizes(room: EcsRoomTypeDef, type: EcsBuildingTypeDef, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var least := room.size_min if room != null else type.min_room
	var most := room.size_max if room != null else type.min_room
	var mid := Vector2i(rng.randi_range(least.x, most.x), rng.randi_range(least.y, most.y))
	var out: Array[Vector2i] = []
	for inner: Vector2i in [mid, least, most]:
		for turned: Vector2i in [inner, Vector2i(inner.y, inner.x)]:
			if not out.has(turned + Vector2i(2, 2)):
				out.append(turned + Vector2i(2, 2))
	return out

## Every spot for a room `outer` big sharing a wall line with a room of `frame` on the sides
## `place` allows (front: beside one, flush with the front; back: behind one; side: beside one),
## each overlapping it by enough for a door.
static func _attachments(frame: Array[Rect2i], outer: Vector2i, place: StringName) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for p in frame:
		if place == &"back" or place == &"any":
			for u in range(p.position.x - outer.x + 3, p.end.x - 2):
				out.append(Rect2i(u, p.end.y - 1, outer.x, outer.y))
		if place != &"back":
			for v in range(p.position.y - outer.y + 3, p.end.y - 2):
				if place == &"front" and v != 0:
					continue
				out.append(Rect2i(p.end.x - 1, v, outer.x, outer.y))
				out.append(Rect2i(p.position.x - outer.x + 1, v, outer.x, outer.y))
	return out

## Whether `rect` and every room of `frame` meet only on their walls.
static func _clear_of(rect: Rect2i, frame: Array[Rect2i]) -> bool:
	for other in frame:
		if rect.grow(-1).intersects(other) or other.grow(-1).intersects(rect):
			return false
	return true

## Cells of wall `rect` shares with the rooms of `frame`.
static func _shared(rect: Rect2i, frame: Array[Rect2i]) -> int:
	var n := 0
	for other in frame:
		var both := rect.intersection(other)
		n += both.size.x * both.size.y
	return n

## Whether adding `rect` leaves open ground inside the footprint that can't reach its edge.
static func _closes_pocket(rect: Rect2i, frame: Array[Rect2i], size: Vector2i) -> bool:
	var solid: Dictionary = {}
	for r in frame + [rect]:
		for cell in EcsBuildRules.cells(r):
			solid[cell] = true
	var open := 0
	var queue: Array[Vector2i] = []
	var seen: Dictionary = {}
	for y in size.y:
		for x in size.x:
			var cell := Vector2i(x, y)
			if solid.has(cell):
				continue
			open += 1
			if x == 0 or y == 0 or x == size.x - 1 or y == size.y - 1:
				seen[cell] = true
				queue.append(cell)
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for side: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next := cell + side
			if next.x < 0 or next.y < 0 or next.x >= size.x or next.y >= size.y or solid.has(next) or seen.has(next):
				continue
			seen[next] = true
			queue.append(next)
	return seen.size() < open

## The building's parts, each walled on its perimeter, two touching parts sharing a wall line:
## {shape, parts}. With more than one room the type's `shapes` may cut the back (away from
## `facing`): an L cuts a back corner, a T both (leaving a wing), a U the middle. A cut that
## would leave a part smaller than a room, or more parts than rooms, is plain.
static func _shape(type: EcsBuildingTypeDef, size: Vector2i, wealth: int, facing: Vector2i,
		rng: RandomNumberGenerator) -> Dictionary:
	var plain := {"shape": &"plain", "parts": [Rect2i(Vector2i.ZERO, size)] as Array[Rect2i]}
	var want: int = EcsBuildingTypeDef.by_wealth(type.rooms, wealth)
	if want < 2 or type.shapes.is_empty():
		return plain
	var total := 0.0
	for key: StringName in type.shapes:
		total += type.shapes[key]
	var roll := rng.randf() * total
	var shape := &"plain"
	for key: StringName in type.shapes:
		roll -= type.shapes[key]
		if roll < 0.0:
			shape = key
			break
	# Frame: u along the front, v from the front (0) to the back (depth - 1).
	var across := size.x if facing.y != 0 else size.y
	var depth := size.y if facing.y != 0 else size.x
	var part_w := type.min_room.x + 2
	var part_d := type.min_room.y + 2
	var cut_d := rng.randi_range(ceili(depth * type.notch.x), floori(depth * type.notch.y))
	cut_d = clampi(cut_d, part_d - 1, depth - part_d)
	if cut_d < part_d - 1 or depth - cut_d < part_d:
		return plain
	var front := Rect2i(0, 0, across, depth - cut_d)
	var back_y := depth - cut_d - 1
	var frame: Array[Rect2i] = []
	match shape:
		&"l":
			var cut_w := clampi(rng.randi_range(ceili(across * type.notch.x), floori(across * type.notch.y)), 2, across - part_w)
			if across - cut_w < part_w or cut_w < 2:
				return plain
			var left := rng.randf() < 0.5
			frame = [front, Rect2i(cut_w if left else 0, back_y, across - cut_w, cut_d + 1)]
		&"t":
			var narrow := across - 2 * floori(across * type.notch.y)
			var wide := across - 2 * ceili(across * type.notch.x)
			var wing := clampi(rng.randi_range(mini(narrow, wide), maxi(narrow, wide)), part_w, across - 4)
			if wing < part_w or across - wing < 4:
				return plain
			var from := rng.randi_range(2, across - wing - 2)
			frame = [front, Rect2i(from, back_y, wing, cut_d + 1)]
		&"u":
			if want < 3:
				return plain
			var gap := clampi(rng.randi_range(ceili(across * type.notch.x), floori(across * type.notch.y)), 2, across - part_w * 2)
			if across - gap < part_w * 2 or gap < 2:
				return plain
			var left_w := rng.randi_range(part_w, across - gap - part_w)
			frame = [front, Rect2i(0, back_y, left_w, cut_d + 1), Rect2i(left_w + gap, back_y, across - left_w - gap, cut_d + 1)]
		_:
			return plain
	var parts: Array[Rect2i] = []
	for rect in frame:
		parts.append(_from_frame(rect, size, facing))
	return {"shape": shape, "parts": parts}

## A rect in the facing frame (u along the front, v back from it) as cells of a `size` footprint.
static func _from_frame(rect: Rect2i, size: Vector2i, facing: Vector2i) -> Rect2i:
	var a := _frame_cell(rect.position, size, facing)
	var b := _frame_cell(rect.end - Vector2i.ONE, size, facing)
	return Rect2i(Vector2i(mini(a.x, b.x), mini(a.y, b.y)), (a - b).abs() + Vector2i.ONE)

static func _frame_cell(cell: Vector2i, size: Vector2i, facing: Vector2i) -> Vector2i:
	if facing == Vector2i.UP:
		return cell
	if facing == Vector2i.DOWN:
		return Vector2i(size.x - 1 - cell.x, size.y - 1 - cell.y)
	if facing == Vector2i.LEFT:
		return Vector2i(cell.y, cell.x)
	return Vector2i(size.x - 1 - cell.y, cell.x)

## Splits the `inside` of each part into rooms, the largest splittable first, until the type's
## count for `wealth`; each split's wall line goes into `walls`.
static func _split(inside: Array[Rect2i], type: EcsBuildingTypeDef, wealth: int, rng: RandomNumberGenerator,
		walls: Dictionary) -> Array[Rect2i]:
	var rooms: Array[Rect2i] = inside.duplicate()
	var want: int = EcsBuildingTypeDef.by_wealth(type.rooms, wealth)
	var least := type.min_room
	while rooms.size() < want:
		var pick := -1
		for k in rooms.size():
			var r := rooms[k]
			if (r.size.x >= least.x * 2 + 1 or r.size.y >= least.y * 2 + 1) \
					and (pick < 0 or r.get_area() > rooms[pick].get_area()):
				pick = k
		if pick < 0:
			break
		var r := rooms[pick]
		var can_x := r.size.x >= least.x * 2 + 1
		var can_y := r.size.y >= least.y * 2 + 1
		var down := can_x and (not can_y or r.size.x > r.size.y or (r.size.x == r.size.y and rng.randi() % 2 == 0))
		if down:
			var x := rng.randi_range(r.position.x + least.x, r.end.x - 1 - least.x)
			for y in range(r.position.y, r.end.y):
				walls[Vector2i(x, y)] = true
			rooms[pick] = Rect2i(r.position, Vector2i(x - r.position.x, r.size.y))
			rooms.append(Rect2i(Vector2i(x + 1, r.position.y), Vector2i(r.end.x - x - 1, r.size.y)))
		else:
			var y := rng.randi_range(r.position.y + least.y, r.end.y - 1 - least.y)
			for x in range(r.position.x, r.end.x):
				walls[Vector2i(x, y)] = true
			rooms[pick] = Rect2i(r.position, Vector2i(r.size.x, y - r.position.y))
			rooms.append(Rect2i(Vector2i(r.position.x, y + 1), Vector2i(r.size.x, r.end.y - y - 1)))
	return rooms

## Cell -> room index, for every room cell.
static func _room_map(rooms: Array[Rect2i]) -> Dictionary:
	var room_of: Dictionary = {}
	for k in rooms.size():
		for cell in EcsBuildRules.cells(rooms[k]):
			room_of[cell] = k
	return room_of

## A perimeter cell on the `facing` side with a room right inside it: `door` when it is one,
## else the one nearest it, else one at random; (-1, -1) when there is none.
static func _entrance(size: Vector2i, facing: Vector2i, room_of: Dictionary, walls: Dictionary,
		rng: RandomNumberGenerator, door: Vector2i = Vector2i(-1, -1)) -> Vector2i:
	var options: Array[Vector2i] = []
	var along := Vector2i(absi(facing.y), absi(facing.x))
	var edge := Vector2i(size.x - 1 if facing.x > 0 else 0, size.y - 1 if facing.y > 0 else 0)
	var length := size.x if along.x != 0 else size.y
	for k in range(1, length - 1):
		var cell := Vector2i(k, edge.y) if along.x != 0 else Vector2i(edge.x, k)
		if room_of.has(cell - facing) and walls.has(cell - along) and walls.has(cell + along):
			options.append(cell)
	if options.is_empty():
		return Vector2i(-1, -1)
	if door != Vector2i(-1, -1):
		var best := options[0]
		for cell in options:
			if Vector2(cell).distance_squared_to(Vector2(door)) < Vector2(best).distance_squared_to(Vector2(door)):
				best = cell
		return best
	return options[rng.randi() % options.size()]

## Inner doors: a random spanning tree over rooms that share a straight stretch of wall, grown
## from the entrance room, and by the type's loop chance one more door on a pair it skipped.
static func _inner_doors(rooms: Array[Rect2i], room_of: Dictionary, walls: Dictionary, first: int,
		type: EcsBuildingTypeDef, rng: RandomNumberGenerator) -> Array[Vector2i]:
	# Pair "a,b" (a < b) -> wall cells a door between them could take.
	var shared: Dictionary = {}
	for cell: Vector2i in walls:
		for across: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			var along := Vector2i(across.y, across.x)
			if not (room_of.has(cell - across) and room_of.has(cell + across)):
				continue
			if not (walls.has(cell - along) and walls.has(cell + along)):
				continue
			var a: int = room_of[cell - across]
			var b: int = room_of[cell + across]
			if a == b:
				continue
			var pair := Vector2i(mini(a, b), maxi(a, b))
			if not shared.has(pair):
				shared[pair] = []
			(shared[pair] as Array).append(cell)
	var pairs: Array = shared.keys()
	pairs.sort()
	var doors: Array[Vector2i] = []
	var reached: Dictionary = {first: true}
	var used: Dictionary = {}
	while reached.size() < rooms.size():
		var open: Array = []
		for pair: Vector2i in pairs:
			if reached.has(pair.x) != reached.has(pair.y):
				open.append(pair)
		if open.is_empty():
			break
		var pick: Vector2i = open[rng.randi() % open.size()]
		var options: Array = shared[pick]
		doors.append(options[rng.randi() % options.size()])
		reached[pick.x] = true
		reached[pick.y] = true
		used[pick] = true
	var spare: Array = pairs.filter(func(pair: Vector2i) -> bool: return not used.has(pair))
	if not spare.is_empty() and rng.randf() < type.loop_chance:
		var options: Array = shared[spare[rng.randi() % spare.size()]]
		doors.append(options[rng.randi() % options.size()])
	return doors

## Each room's role: the type's list by room size, largest first.
static func _roles(rooms: Array[Rect2i], type: EcsBuildingTypeDef) -> Array[StringName]:
	var order: Array = range(rooms.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		return rooms[a].get_area() > rooms[b].get_area() or (rooms[a].get_area() == rooms[b].get_area() and a < b))
	var roles: Array[StringName] = []
	roles.resize(rooms.size())
	for rank in order.size():
		roles[order[rank]] = type.roles[mini(rank, type.roles.size() - 1)] if not type.roles.is_empty() else &""
	return roles

## Places `pieces` in `room`, in order: [cell, blueprint, turns] for each that fits; those that
## don't go to `missing`. A door's inside neighbour stays free, and the free cells stay one area.
static func _furnish(room: Rect2i, pieces: Array[StringName], doors: Array[Vector2i],
		entities: EcsEntityCatalog, rng: RandomNumberGenerator, missing: Array[StringName],
		layout: Dictionary[StringName, StringName] = {}) -> Array:
	var frame := _door_frame(room, doors)
	var taken: Dictionary = {}
	for door in doors:
		for side: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if room.has_point(door + side):
				taken[door + side] = false  # kept free, not furnished
	var placed: Array = []
	for blueprint in pieces:
		var place := EcsBuildRules.template(entities, blueprint, &"grid_position") as EcsGridPositionComponent
		var furniture := EcsBuildRules.template(entities, blueprint, &"furniture") as EcsFurnitureComponent
		var size := place.size if place != null else Vector2i.ONE
		var to_wall := furniture != null and furniture.against_wall
		var fits: Array = []
		var loose: Array = []
		for turns in 4:
			var covers := EcsTownGrid.turned(size, turns)
			for y in range(room.position.y, room.end.y - covers.y + 1):
				for x in range(room.position.x, room.end.x - covers.x + 1):
					var rect := Rect2i(Vector2i(x, y), covers)
					if not _free(rect, taken):
						continue
					var touches := _touches(room, rect)
					if to_wall:
						if _back_to_wall(room, rect, turns):
							fits.append([rect.position, turns])
					elif touches:
						loose.append([rect.position, turns])
					else:
						fits.append([rect.position, turns])
		# A piece with a place in the door's frame takes the best spot there that keeps the room one area;
		# when there is none it falls back to anywhere, as before.
		var pick: Array = []
		var where: StringName = layout.get(blueprint, &"")
		if where != &"" and not frame.is_empty():
			var spots: Array = (fits + loose).filter(func(spot: Array) -> bool:
				return _fits_place(room, Rect2i(spot[0], EcsTownGrid.turned(size, spot[1])), spot[1], where, frame, to_wall))
			spots.sort_custom(func(x: Array, y: Array) -> bool:
				return _place_score(room, Rect2i(x[0], EcsTownGrid.turned(size, x[1])), where, frame) \
					< _place_score(room, Rect2i(y[0], EcsTownGrid.turned(size, y[1])), where, frame))
			for spot: Array in spots:
				if _stays_one_area(room, Rect2i(spot[0], EcsTownGrid.turned(size, spot[1])), taken):
					pick = spot
					break
		# The flood fill only for the spot drawn; one that splits the room is dropped and another drawn.
		# Spots off the way in from the door first, when the room has a door.
		var tiers: Array = [fits, loose]
		if not frame.is_empty():
			var off := func(spot: Array) -> bool:
				return not _on_way(room, Rect2i(spot[0], EcsTownGrid.turned(size, spot[1])), frame)
			tiers = [fits.filter(off), loose.filter(off), fits, loose]
		for options: Array in tiers:
			while pick.is_empty() and not options.is_empty():
				var k := rng.randi() % options.size()
				var spot: Array = options[k]
				if _stays_one_area(room, Rect2i(spot[0], EcsTownGrid.turned(size, spot[1])), taken):
					pick = spot
				else:
					options.remove_at(k)
		if pick.is_empty():
			missing.append(blueprint)
			continue
		for cell in EcsBuildRules.cells(Rect2i(pick[0], EcsTownGrid.turned(size, pick[1]))):
			taken[cell] = true
		placed.append([pick[0], blueprint, pick[1]])
	return placed

## The room seen from its main door (the first door touching it: the entrance, or the one toward
## it): {door: the cell inside it, back: the direction from the door to the back wall}; empty with
## no door.
static func _door_frame(room: Rect2i, doors: Array[Vector2i]) -> Dictionary:
	for door in doors:
		for side: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if room.has_point(door + side) and not room.has_point(door):
				return {"door": door + side, "back": side}
	return {}

## Whether `rect` (turned `turns`) stands where `where` says in the door's frame. The way in, the
## line of cells from the door to the back wall, is kept free by every place but `back`.
static func _fits_place(room: Rect2i, rect: Rect2i, turns: int, where: StringName, frame: Dictionary, to_wall: bool) -> bool:
	var back: Vector2i = frame["back"]
	var inside: Vector2i = frame["door"]
	var across := Vector2i(absi(back.y), absi(back.x))
	var on_way := _on_way(room, rect, frame)
	var at_back := _on_edge(room, rect, back)
	var at_side := _on_edge(room, rect, across) or _on_edge(room, rect, -across)
	var faces_in := func(side: Vector2i) -> bool: return not to_wall or _back_to(rect, turns, room, side)
	match where:
		&"back":
			return at_back and faces_in.call(back)
		&"side":
			return at_side and not on_way and (faces_in.call(across) or faces_in.call(-across))
		&"corner":
			return at_back and at_side and not on_way
		&"beside_door":
			return _on_edge(room, rect, -back) and not on_way and rect.grow(1).has_point(inside)
		&"centre":
			return not on_way and not (at_back or at_side or _on_edge(room, rect, -back))
		&"rows":
			return not on_way
	return true

## Whether `rect` covers a cell of the way in: the line from the door to the back wall.
static func _on_way(room: Rect2i, rect: Rect2i, frame: Dictionary) -> bool:
	var at: Vector2i = frame["door"]
	while room.has_point(at):
		if rect.has_point(at):
			return true
		at += frame["back"]
	return false

## Lower is better: `back` and `centre` near the middle, the others nearer the back wall.
static func _place_score(room: Rect2i, rect: Rect2i, where: StringName, frame: Dictionary) -> float:
	var mid := Vector2(room.position) + Vector2(room.size) / 2.0
	var centre := Vector2(rect.position) + Vector2(rect.size) / 2.0
	if where == &"back" or where == &"centre":
		return centre.distance_squared_to(mid)
	return centre.distance_squared_to(mid + Vector2(frame["back"]) * Vector2(room.size) / 2.0)

## Whether `rect` touches `room`'s edge in direction `side`.
static func _on_edge(room: Rect2i, rect: Rect2i, side: Vector2i) -> bool:
	if side == Vector2i.UP:
		return rect.position.y == room.position.y
	if side == Vector2i.DOWN:
		return rect.end.y == room.end.y
	if side == Vector2i.LEFT:
		return rect.position.x == room.position.x
	return rect.end.x == room.end.x

## Whether a piece turned `turns` on `rect` has its back on `room`'s edge in direction `side`.
static func _back_to(rect: Rect2i, turns: int, room: Rect2i, side: Vector2i) -> bool:
	var faces: Vector2i = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT][posmod(turns, 4)]
	return faces == side and _on_edge(room, rect, side)

static func _free(rect: Rect2i, taken: Dictionary) -> bool:
	for cell in EcsBuildRules.cells(rect):
		if taken.has(cell):
			return false
	return true

## Whether `room`'s cells left unfurnished, with `rect` furnished too, are still one area.
static func _stays_one_area(room: Rect2i, rect: Rect2i, taken: Dictionary) -> bool:
	var open: Array[Vector2i] = []
	for cell in EcsBuildRules.cells(room):
		if not rect.has_point(cell) and taken.get(cell, false) != true:
			open.append(cell)
	if open.is_empty():
		return false
	var seen: Dictionary = {open[0]: true}
	var queue: Array[Vector2i] = [open[0]]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for side: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next := cell + side
			if room.has_point(next) and not seen.has(next) and not rect.has_point(next) and taken.get(next, false) != true:
				seen[next] = true
				queue.append(next)
	return seen.size() == open.size()

static func _touches(room: Rect2i, rect: Rect2i) -> bool:
	return rect.position.x == room.position.x or rect.position.y == room.position.y \
		or rect.end.x == room.end.x or rect.end.y == room.end.y

## Whether a piece turned `turns` on `rect` has its back on `room`'s edge: its back is its top
## edge as drawn, facing up, right, down or left after 0-3 quarter turns.
static func _back_to_wall(room: Rect2i, rect: Rect2i, turns: int) -> bool:
	match posmod(turns, 4):
		0:
			return rect.position.y == room.position.y
		1:
			return rect.end.x == room.end.x
		2:
			return rect.end.y == room.end.y
	return rect.position.x == room.position.x
