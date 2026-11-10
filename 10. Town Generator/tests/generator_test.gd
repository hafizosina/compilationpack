extends Node2D

## Step 7's acceptance test: for each building type, 1,000 seeds — sizes, wealth levels and
## facings drawn from the seed — generated, sent through the real build system and room
## detection, and checked: every command accepted, every room has a door and is reachable
## from the entrance, no furniture blocks a door, the same seed gives the same building.
## Prints the generator's cost.
##
##   "$GODOT" --headless --path . "res://10. Town Generator/tests/generator_test.tscn"
##
## Exits 0 only if every check passes.

const CATALOG := preload("res://10. Town Generator/defs/town_catalog.tres")
const ENTITIES := preload("res://10. Town Generator/defs/entity_catalog.tres")
const SEEDS: int = 1000
const FACINGS: Array[Vector2i] = [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]

var _checks: int = 0
var _failures: int = 0

func _ready() -> void:
	CATALOG.number()
	for type in CATALOG.building_types:
		_check_type(type)
	_check_cut_sides()
	print("[gen] %d/%d checks passed" % [_checks - _failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)

## The inputs seed `n` stands for: size, wealth and facing, all from the seed.
func _inputs(type: EcsBuildingTypeDef, n: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = n * 7919 + 17
	return {
		"size": Vector2i(rng.randi_range(type.min_size.x, type.max_size.x), rng.randi_range(type.min_size.y, type.max_size.y)),
		"wealth": n % 3,
		"facing": FACINGS[(n / 3) % 4],
	}

func _check_type(type: EcsBuildingTypeDef) -> void:
	var refused: Array = []
	var bad: Dictionary = {}
	var drifted: Array = []
	var mistyped: int = 0
	var missing: int = 0
	var rooms: int = 0
	var generate_usec: int = 0
	var worst_usec: int = 0
	var shapes: Dictionary = {}
	var cut_rooms: int = 0
	for n in SEEDS:
		var input := _inputs(type, n)
		var started := Time.get_ticks_usec()
		var plan := EcsBuildingGenerator.plan(type, input.size, input.wealth, input.facing, n, CATALOG, ENTITIES, Vector2i.ONE)
		var spent := Time.get_ticks_usec() - started
		generate_usec += spent
		worst_usec = maxi(worst_usec, spent)
		var again := EcsBuildingGenerator.generate(type, input.size, input.wealth, input.facing, n, CATALOG, ENTITIES, Vector2i.ONE)
		if _text(again) != _text(plan.commands):
			drifted.append(n)
		var t := _build(input.size + Vector2i(2, 2), plan.commands)
		for command: EcsBuildCommand in plan.commands:
			if command.result != &"ok":
				refused.append("seed %d: %s at %s %s" % [n, EcsBuildCommand.Kind.keys()[command.kind], command.cell, command.result])
				break
		var grid := t.grid as EcsTownGridSingleton
		var building_id := grid.building_id[EcsTownGrid.index(grid, Vector2i.ONE)]
		for problem in EcsBuildingCheck.problems(t.world, grid, building_id, plan.entrance):
			var kind := problem.get_slice(" at ", 0) if " at " in problem else problem
			if not bad.has(kind):
				bad[kind] = []
			(bad[kind] as Array).append("seed %d: %s" % [n, problem])
		missing += (plan.missing as Array).size()
		shapes[plan.shape] = int(shapes.get(plan.shape, 0)) + 1
		var in_shape: Dictionary = {}
		for cell: Vector2i in plan.cells:
			in_shape[cell] = true
		for cell in EcsBuildRules.cells(Rect2i(Vector2i.ONE, input.size)):
			if not in_shape.has(cell) and grid.room_id[EcsTownGrid.index(grid, cell)] != EcsTownGridSingleton.NO_ID:
				cut_rooms += 1
		var building := (t.world as EcsWorld).get_component(building_id, EcsBuildingComponent) as EcsBuildingComponent
		rooms += plan.rooms.size()
		for room: Dictionary in plan.rooms:
			var cell: Vector2i = (room.rect as Rect2i).position
			var detected := grid.room_id[EcsTownGrid.index(grid, cell)]
			for record: Dictionary in building.rooms:
				if record["id"] == detected and record["type"] != room.role:
					mistyped += 1
		(t.root as Node).free()
	var name := String(type.key)
	_check("%s: %d seeds, every command accepted%s" % [name, SEEDS, _first(refused)], refused.is_empty())
	for kind: String in ["sealed area", "room", "door", "furniture blocks the door", "no entrance", "no building"]:
		var found: Array = bad.get(kind, [])
		_check("%s: %s" % [name, {
			"sealed area": "no sealed area: every room has a door",
			"room": "every room reachable from the entrance",
			"door": "every door reachable from the entrance",
			"furniture blocks the door": "no furniture on a door's inside neighbour",
			"no entrance": "an entrance on the facing side",
			"no building": "a building",
		}[kind] + _first(found)], found.is_empty())
	_check("%s: the same seed gives the same building%s" % [name, "" if drifted.is_empty() else " (not seeds %s)" % [drifted.slice(0, 5)]],
		drifted.is_empty())
	_check("%s: every room typed as its role by room detection (%d rooms, %d mistyped)" % [name, rooms, mistyped], mistyped == 0)
	var shaped := shapes.keys().filter(func(k: StringName) -> bool: return k != &"plain").size()
	_check("%s: shapes %s; no cut corner is a room" % [name, shapes], cut_rooms == 0 and (type.shapes.size() <= 1 or shaped > 0))
	print("[gen] measure: %s, %d buildings: generator %.0f µs each on average, %d µs at worst; %d rooms; %d optional pieces had no room" % [
		name, SEEDS, float(generate_usec) / SEEDS, worst_usec, rooms, missing])

## A building cut in two, as in a chunk: its left part alone, with its right side marked cut,
## keeps every interior cell on that side in a room or sealed region; unmarked, the cut rooms leak.
func _check_cut_sides() -> void:
	var type := CATALOG.building_types[0]
	var kept := 0
	var leaked := 0
	var cells := 0
	for n in 50:
		var size := Vector2i(12, 9)
		var plan := EcsBuildingGenerator.plan(type, size, 2, Vector2i.UP, n, CATALOG, ENTITIES, Vector2i.ONE)
		var half := Rect2i(Vector2i.ONE, Vector2i(size.x / 2, size.y))
		var walled: Dictionary = {}
		for command: EcsBuildCommand in plan.commands:
			if command.kind == EcsBuildCommand.Kind.PLACE_WALL or command.kind == EcsBuildCommand.Kind.PLACE_DOOR:
				walled[command.cell] = true
		for marked in [true, false]:
			var commands: Array[EcsBuildCommand] = [EcsBuildCommand.create_building(half, false, EcsBuildingComponent.CUT_RIGHT if marked else 0)]
			for command: EcsBuildCommand in plan.commands:
				if command.kind != EcsBuildCommand.Kind.CREATE_BUILDING and command.kind != EcsBuildCommand.Kind.PLACE_OBJECT \
						and half.has_point(command.cell):
					commands.append(command)
			var t := _build(half.end + Vector2i.ONE, commands)
			var grid := t.grid as EcsTownGridSingleton
			var building := (t.world as EcsWorld).get_component(grid.building_id[EcsTownGrid.index(grid, Vector2i.ONE)], EcsBuildingComponent) as EcsBuildingComponent
			var covered: Dictionary = {}
			for room: Dictionary in building.rooms:
				for cell: Vector2i in room["cells"]:
					covered[cell] = true
			for cell in EcsBuildRules.cells(half):
				if walled.has(cell) or not (plan.cells as Array).has(cell):
					continue
				if marked:
					cells += 1
					kept += 1 if covered.has(cell) else 0
				elif not covered.has(cell):
					leaked += 1
			(t.root as Node).free()
	_check("a building cut in two keeps %d of %d interior cells in rooms with its cut side marked (%d lost unmarked)" % [kept, cells, leaked],
		kept == cells and leaked > 0)

func _first(found: Array) -> String:
	return "" if found.is_empty() else " (%d, first: %s)" % [found.size(), found[0]]

## A world of `size` with lifecycle, build and room detection, `commands` sent and settled.
func _build(size: Vector2i, commands: Array) -> Dictionary:
	var world := EcsWorld.new()
	world.add_singleton(EcsTownGrid.make(size.x, size.y, CATALOG.terrain_id(&"grass")))
	world.add_singleton(EcsLifecycleSingleton.new())
	var root := Node2D.new()
	add_child(root)
	var scheduler := EcsScheduler.new()
	scheduler.add(EcsLifecycleSystem.new(EcsEntityManager.new(root), ENTITIES)) \
		.add(EcsBuildCommandSystem.new(CATALOG, ENTITIES)).add(EcsRoomDetectionSystem.new(CATALOG))
	var grid := world.get_singleton(EcsTownGridSingleton) as EcsTownGridSingleton
	for command: EcsBuildCommand in commands:
		grid.commands.append(command)
	for k in 3:
		scheduler.run_all(world, 0.0)
	return {"world": world, "grid": grid, "root": root}

func _text(commands: Array) -> String:
	var lines: PackedStringArray = []
	for command: EcsBuildCommand in commands:
		lines.append("%d %s %d %s %s" % [command.kind, command.cell, command.value, command.blueprint, command.rect])
	return "\n".join(lines)

func _check(what: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
	print("[gen] %s  %s" % ["ok  " if passed else "FAIL", what])
