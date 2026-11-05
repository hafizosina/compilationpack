class_name EcsBuildingGenerator
extends RefCounted

## Pure and seeded: lays out a building of a type, wealth and size and gives back the build
## commands the player's tools send, so everything downstream is the tested path. The same
## inputs always give the same commands.
##   1. Rooms: the footprint split by binary space partition, never below the type's smallest room.
##   2. Walls: the perimeter and the splits.
##   3. Doors: the entrance on the facing side; inner doors along a spanning tree of the rooms,
##      so every room is reachable, and by chance one more, making a loop.
##   4. Roles from the type's list, largest room first.
##   5. Floor by wealth; the poorest has none.
##   6. Furniture by role, turned to fit, against a wall or free-standing, never on a door's
##      inside neighbour and never cutting a room in two.

## The commands for a building of `type` with its top-left at `at`.
static func generate(type: EcsBuildingTypeDef, size: Vector2i, wealth: int, facing: Vector2i,
		rng_seed: int, catalog: EcsTownCatalog, entities: EcsEntityCatalog, at: Vector2i = Vector2i.ZERO) -> Array[EcsBuildCommand]:
	return plan(type, size, wealth, facing, rng_seed, catalog, entities, at)["commands"]

## The layout behind `generate`, for checks and viewers: {commands, rooms: [{rect, role}],
## entrance, doors, missing: [blueprints that found no place]}, all cells at `at`.
static func plan(type: EcsBuildingTypeDef, size: Vector2i, wealth: int, facing: Vector2i,
		rng_seed: int, catalog: EcsTownCatalog, entities: EcsEntityCatalog, at: Vector2i = Vector2i.ZERO) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var walls: Dictionary = {}
	for y in size.y:
		for x in size.x:
			if x == 0 or y == 0 or x == size.x - 1 or y == size.y - 1:
				walls[Vector2i(x, y)] = true
	var rooms := _split(Rect2i(Vector2i.ONE, size - Vector2i(2, 2)), type, wealth, rng, walls)
	var room_of := _room_map(rooms)
	var entrance := _entrance(size, facing, room_of, walls, rng)
	var doors: Array[Vector2i] = []
	if entrance != Vector2i(-1, -1):
		doors.append(entrance)
		doors.append_array(_inner_doors(rooms, room_of, walls, room_of[entrance - facing], type, rng))
	var roles := _roles(rooms, type)
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
		for placed in _furnish(rooms[k], pieces, doors, entities, rng, missing):
			out.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, at + placed[0], placed[1], placed[2]))
	var listed: Array = []
	for k in rooms.size():
		listed.append({"rect": Rect2i(at + rooms[k].position, rooms[k].size), "role": roles[k]})
	var placed_doors: Array[Vector2i] = []
	for cell in doors:
		placed_doors.append(at + cell)
	return {"commands": out, "rooms": listed, "entrance": at + entrance if entrance != Vector2i(-1, -1) else entrance,
		"doors": placed_doors, "missing": missing}

## Splits `inside` into rooms, the largest splittable first, until the type's count for
## `wealth`; each split's wall line goes into `walls`.
static func _split(inside: Rect2i, type: EcsBuildingTypeDef, wealth: int, rng: RandomNumberGenerator,
		walls: Dictionary) -> Array[Rect2i]:
	var rooms: Array[Rect2i] = [inside]
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

## A perimeter cell on the `facing` side with a room right inside it, or (-1, -1).
static func _entrance(size: Vector2i, facing: Vector2i, room_of: Dictionary, walls: Dictionary,
		rng: RandomNumberGenerator) -> Vector2i:
	var options: Array[Vector2i] = []
	var along := Vector2i(absi(facing.y), absi(facing.x))
	var edge := Vector2i(size.x - 1 if facing.x > 0 else 0, size.y - 1 if facing.y > 0 else 0)
	var length := size.x if along.x != 0 else size.y
	for k in range(1, length - 1):
		var cell := Vector2i(k, edge.y) if along.x != 0 else Vector2i(edge.x, k)
		if room_of.has(cell - facing) and walls.has(cell - along) and walls.has(cell + along):
			options.append(cell)
	return options[rng.randi() % options.size()] if not options.is_empty() else Vector2i(-1, -1)

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
		entities: EcsEntityCatalog, rng: RandomNumberGenerator, missing: Array[StringName]) -> Array:
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
		# The flood fill only for the spot drawn; one that splits the room is dropped and another drawn.
		var pick: Array = []
		for options: Array in [fits, loose]:
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
