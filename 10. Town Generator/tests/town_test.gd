extends Node2D

## Headless test for module 10.
##
##   "$GODOT" --headless --path . "res://10. Town Generator/tests/town_test.tscn"
##
## Exits 0 only if every check passes.

const CATALOG := preload("res://10. Town Generator/defs/town_catalog.tres")
const MAIN := preload("res://10. Town Generator/main.tscn")
const GRASS: int = 1
const DIRT: int = 2
const WATER: int = 4
const WOOD: int = 1
const RUG: int = 4

var _checks: int = 0
var _failures: int = 0

func _ready() -> void:
	_the_authors_art_is_used_and_its_layout_read()
	_commands_are_validated()
	_a_change_redraws_only_its_corners()
	_terrain_blends_and_lower_types_fill_under()
	_a_floor_never_bleeds_past_its_cells()
	_walls_join_their_neighbours()
	_measure()
	print("[town] %d/%d checks passed" % [_checks - _failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)

## A world with a grid, the build system and the tile sync, drawn once.
func _setup(size: Vector2i) -> Dictionary:
	var world := EcsWorld.new()
	world.add_singleton(EcsTownGrid.make(size.x, size.y, GRASS))
	# The scene's own tile layers, taken out of main.tscn: nothing is built in code.
	var main := MAIN.instantiate()
	var root := main.get_node("World/TilemapGroup")
	root.get_parent().remove_child(root)
	main.free()
	add_child(root)
	var build := EcsBuildCommandSystem.new(CATALOG)
	var sync := EcsTileSyncSystem.new(root, CATALOG)
	var scheduler := EcsScheduler.new()
	scheduler.add(build).add(sync)
	scheduler.run_all(world, 0.0)
	_sync_for_mask = sync
	return {"world": world, "grid": world.get_singleton(EcsTownGridSingleton), "build": build,
		"sync": sync, "scheduler": scheduler, "root": root}

func _send(t: Dictionary, commands: Array[EcsBuildCommand]) -> void:
	(t.grid as EcsTownGridSingleton).commands.append_array(commands)
	(t.scheduler as EcsScheduler).run_all(t.world, 0.0)

func _cmd(kind: EcsBuildCommand.Kind, cell: Vector2i, value: int = 0) -> EcsBuildCommand:
	return EcsBuildCommand.make(kind, cell, value)

func _commands_are_validated() -> void:
	var t := _setup(Vector2i(8, 8))
	var grid := t.grid as EcsTownGridSingleton
	var outside := _cmd(EcsBuildCommand.Kind.SET_TERRAIN, Vector2i(8, 0), DIRT)
	var unknown := _cmd(EcsBuildCommand.Kind.SET_TERRAIN, Vector2i(1, 1), 99)
	var no_floor := _cmd(EcsBuildCommand.Kind.SET_FLOOR, Vector2i(1, 1), 99)
	var good := _cmd(EcsBuildCommand.Kind.SET_TERRAIN, Vector2i(1, 1), DIRT)
	_send(t, [outside, unknown, no_floor, good])
	_check("a cell off the grid is refused", outside.result == &"out_of_bounds")
	_check("an unknown terrain or floor is refused",
		unknown.result == &"unknown_terrain" and no_floor.result == &"unknown_floor")
	_check("a good one is applied", good.result == &"ok" and grid.terrain[EcsTownGrid.index(grid, Vector2i(1, 1))] == DIRT)
	_check("and the inbox is emptied", grid.commands.is_empty() and grid.dirty.is_empty())
	t.root.queue_free()

func _a_change_redraws_only_its_corners() -> void:
	var t := _setup(Vector2i(16, 16))
	var sync := t.sync as EcsTileSyncSystem
	_check("the first run draws the whole base layer",
		sync.terrain_layers()[0].get_used_cells().size() == 17 * 17)
	_send(t, [_cmd(EcsBuildCommand.Kind.SET_TERRAIN, Vector2i(5, 5), DIRT)])
	_check("one terrain cell redraws its 4 corners on each terrain layer",
		sync.redrawn == 4 * CATALOG.terrains.size())
	_send(t, [_cmd(EcsBuildCommand.Kind.SET_FLOOR, Vector2i(5, 5), WOOD)])
	_check("one floor cell redraws its 4 corners on each floor layer only",
		sync.redrawn == 4 * CATALOG.floors.size())
	_send(t, [_cmd(EcsBuildCommand.Kind.SET_FLOOR, Vector2i(5, 5), WOOD)])
	_check("setting what is already there redraws nothing", sync.redrawn == 0)
	t.root.queue_free()

func _terrain_blends_and_lower_types_fill_under() -> void:
	var t := _setup(Vector2i(10, 10))
	var sync := t.sync as EcsTileSyncSystem
	_send(t, [_cmd(EcsBuildCommand.Kind.SET_TERRAIN, Vector2i(4, 4), WATER)])
	var grass := sync.terrain_layers()[0]
	var water := sync.terrain_layers()[3]
	_check("water's corner tiles each show one quadrant of it",
		_mask(water, Vector2i(4, 4)) == EcsDualGrid.BR and _mask(water, Vector2i(5, 4)) == EcsDualGrid.BL
		and _mask(water, Vector2i(4, 5)) == EcsDualGrid.TR and _mask(water, Vector2i(5, 5)) == EcsDualGrid.TL)
	_check("and nothing else is drawn on its layer", water.get_used_cells().size() == 4)
	_check("grass stays whole under it, so no hole shows through the rounded edge",
		_mask(grass, Vector2i(4, 4)) == 15 and _mask(grass, Vector2i(5, 5)) == 15)
	var dirt := sync.terrain_layers()[1]
	_check("types between fill under the higher one too", _mask(dirt, Vector2i(5, 5)) == EcsDualGrid.TL)
	t.root.queue_free()

## Every quadrant drawn on a floor layer is a quarter of a cell with that floor or a higher
## one, and every floor cell is fully drawn: wood shows exactly where wood is.
func _a_floor_never_bleeds_past_its_cells() -> void:
	var t := _setup(Vector2i(12, 12))
	var grid := t.grid as EcsTownGridSingleton
	var sync := t.sync as EcsTileSyncSystem
	var plan: Array[EcsBuildCommand] = []
	for x in range(2, 6):
		for y in range(2, 5):
			plan.append(_cmd(EcsBuildCommand.Kind.SET_FLOOR, Vector2i(x, y), WOOD))
	# Two cells touching only at a corner, and a rug inside the planks.
	plan.append(_cmd(EcsBuildCommand.Kind.SET_FLOOR, Vector2i(8, 8), WOOD))
	plan.append(_cmd(EcsBuildCommand.Kind.SET_FLOOR, Vector2i(9, 9), WOOD))
	plan.append(_cmd(EcsBuildCommand.Kind.SET_FLOOR, Vector2i(3, 3), RUG))
	_send(t, plan)
	var wood := sync.floor_layers()[0]
	var exact := true
	for y in grid.height + 1:
		for x in grid.width + 1:
			var at := Vector2i(x, y)
			var drawn := _mask(wood, at)
			for q in 4:
				var cell: Vector2i = at + EcsDualGrid.CORNERS[q]
				var has := EcsTownGrid.in_bounds(grid, cell) and grid.floor[EcsTownGrid.index(grid, cell)] != 0
				if has != bool(drawn & EcsDualGrid.BITS[q]):
					exact = false
	_check("wood covers its cells exactly, never past them", exact)
	_check("cells touching only at a corner draw the diagonal tile",
		wood.get_cell_atlas_coords(Vector2i(9, 9)) == Vector2i(5, 0))
	_send(t, [_cmd(EcsBuildCommand.Kind.CLEAR_FLOOR, Vector2i(8, 8)), _cmd(EcsBuildCommand.Kind.CLEAR_FLOOR, Vector2i(9, 9))])
	_check("clearing a floor erases its tiles", wood.get_cell_source_id(Vector2i(9, 9)) == -1
		and wood.get_cell_source_id(Vector2i(10, 10)) == -1)
	t.root.queue_free()

## Prints tile sync and command costs; checks only that idle runs cost nothing.
func _measure() -> void:
	for side in [64, 128, 256]:
		var started := Time.get_ticks_usec()
		var t := _setup(Vector2i(side, side))
		var full := Time.get_ticks_usec() - started
		var sync := t.sync as EcsTileSyncSystem
		var build := t.build as EcsBuildCommandSystem
		var per_change := 0
		var per_command := 0
		var n := 200
		for i in n:
			var cell := Vector2i(i * 7 % side, i * 13 % side)
			var kind := EcsBuildCommand.Kind.SET_TERRAIN if i % 2 == 0 else EcsBuildCommand.Kind.SET_FLOOR
			_send(t, [_cmd(kind, cell, DIRT if i % 2 == 0 else WOOD)])
			per_change += sync.last_usec
			per_command += build.last_usec
		started = Time.get_ticks_usec()
		for i in 100:
			(t.scheduler as EcsScheduler).run_all(t.world, 0.0)
		var idle := float(Time.get_ticks_usec() - started) / 100.0
		print("[town] %dx%d: first draw %d ms; one cell: tile sync %.0f µs, command %.1f µs; idle tick %.1f µs"
			% [side, side, full / 1000, float(per_change) / n, float(per_command) / n, idle])
		_check("an idle %d² grid redraws nothing" % side, sync.redrawn == 0)
		t.root.queue_free()

var _sync_for_mask: EcsTileSyncSystem

func _mask(layer: TileMapLayer, at: Vector2i) -> int:
	return _sync_for_mask.mask_at(layer, at)

## The layers are the scene's: the author's grass and WoodFloor, placeholders where there
## is no art; draw order is scene order; layouts come from peering bits or transparency.
func _the_authors_art_is_used_and_its_layout_read() -> void:
	var t := _setup(Vector2i(4, 4))
	var sync := t.sync as EcsTileSyncSystem
	var sheet := func(layer: TileMapLayer) -> String:
		return (layer.tile_set.get_source(layer.tile_set.get_source_id(0)) as TileSetAtlasSource).texture.resource_path
	var names: Array[String] = []
	for layer in sync.terrain_layers() + sync.floor_layers():
		names.append(String(layer.name))
	_check("it fills the scene's layers, in scene order",
		names == ["GroundLayer", "DirtLayer", "SandLayer", "WaterLayer", "FloorLayer", "StoneLayer", "RoadLayer", "RugLayer"])
	_check("grass is the author's sheet", sheet.call(sync.terrain_layers()[0]).ends_with("Tilemap/grassTileset.png"))
	_check("wood is the author's WoodFloor", sheet.call(sync.floor_layers()[0]).ends_with("Tilemap/WoodFloor.png"))
	_check("dirt, with no art given, is the placeholder", sheet.call(sync.terrain_layers()[1]).ends_with("placeholder/terrain_dirt.png"))
	var complete := true
	for layer in sync.terrain_layers() + sync.floor_layers():
		if EcsDualGrid.corner_layout(layer.tile_set.get_source(layer.tile_set.get_source_id(0))).size() != 15:
			complete = false
	_check("every layer's layout reads complete, 15 masks", complete)
	var wood_set := sync.floor_layers()[0].tile_set
	var wood := EcsDualGrid.corner_layout(wood_set.get_source(wood_set.get_source_id(0)))
	_check("WoodFloor's painted peering bits read as its table", _same_layout(wood, EcsDualGrid.CORNER_ATLAS))
	var grass_set := sync.terrain_layers()[0].tile_set
	var grass := EcsDualGrid.corner_layout(grass_set.get_source(grass_set.get_source_id(0)))
	_check("the 16 px grass, read from transparency: diagonals at 3:2 and 4:2, 10 full variants",
		grass[EcsDualGrid.TL | EcsDualGrid.BR] == [Vector2i(3, 2)]
		and grass[EcsDualGrid.TR | EcsDualGrid.BL] == [Vector2i(4, 2)]
		and (grass[EcsDualGrid.FULL] as Array).size() == 10)
	_check("and the scene draws it at 2x", sync.terrain_layers()[0].scale == Vector2(2, 2))
	var walls := sync.wall_layer().tile_set
	_check("WoodWall's peering bits and BaseWall's transparency both read all 16 wall shapes",
		_same_layout(EcsDualGrid.side_layout(walls.get_source(1)), EcsDualGrid.SIDE_ATLAS)
		and EcsDualGrid.side_layout(walls.get_source(3)).size() == 16)
	t.root.queue_free()

func _same_layout(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for mask: int in b:
		if not a.has(mask) or (a[mask] as Array).size() != (b[mask] as Array).size():
			return false
		for coords in b[mask]:
			if not (a[mask] as Array).has(coords):
				return false
	return true

## Walls join every neighbouring wall; placing or removing one redraws it and its four
## neighbours only.
func _walls_join_their_neighbours() -> void:
	var t := _setup(Vector2i(10, 10))
	var grid := t.grid as EcsTownGridSingleton
	var sync := t.sync as EcsTileSyncSystem
	var plan: Array[EcsBuildCommand] = []
	for cell in [Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2), Vector2i(5, 3), Vector2i(5, 4)]:
		plan.append(_cmd(EcsBuildCommand.Kind.PLACE_WALL, cell, 1))
	_send(t, plan)
	var R := EcsDualGrid.RIGHT
	var B := EcsDualGrid.BOTTOM
	var L := EcsDualGrid.LEFT
	var T := EcsDualGrid.TOP
	_check("an L of walls: an end, a run, a corner and an end",
		sync.wall_mask_at(Vector2i(2, 2)) == R and sync.wall_mask_at(Vector2i(3, 2)) == R | L
		and sync.wall_mask_at(Vector2i(5, 2)) == L | B and sync.wall_mask_at(Vector2i(5, 4)) == T)
	_send(t, [_cmd(EcsBuildCommand.Kind.REMOVE_STRUCTURE, Vector2i(4, 2))])
	_check("removing one ends its neighbours", sync.wall_layer().get_cell_source_id(Vector2i(4, 2)) == -1
		and sync.wall_mask_at(Vector2i(3, 2)) == L and sync.wall_mask_at(Vector2i(5, 2)) == B)
	_check("and redraws only it and its four neighbours", sync.redrawn <= 5)
	var stone := _cmd(EcsBuildCommand.Kind.PLACE_WALL, Vector2i(8, 8), 2)
	var unknown := _cmd(EcsBuildCommand.Kind.PLACE_WALL, Vector2i(7, 7), 99)
	grid.object_id[EcsTownGrid.index(grid, Vector2i(1, 8))] = 123
	var blocked := _cmd(EcsBuildCommand.Kind.PLACE_WALL, Vector2i(1, 8), 1)
	_send(t, [stone, unknown, blocked])
	_check("a stone wall draws from its own source, a lone post",
		sync.wall_layer().get_cell_source_id(Vector2i(8, 8)) == 3 and sync.wall_mask_at(Vector2i(8, 8)) == 0)
	_check("an unknown wall type, or a cell with an object, is refused",
		unknown.result == &"unknown_wall" and blocked.result == &"occupied")
	t.root.queue_free()

func _check(what: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
	print("[town] %s  %s" % ["ok  " if passed else "FAIL", what])
