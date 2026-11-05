extends Node2D

## Headless test for module 10.
##
##   "$GODOT" --headless --path . "res://10. Town Generator/tests/town_test.tscn"
##
## Exits 0 only if every check passes.

const CATALOG := preload("res://10. Town Generator/defs/town_catalog.tres")
const MAIN := preload("res://10. Town Generator/main.tscn")
const ENTITIES := preload("res://10. Town Generator/defs/entity_catalog.tres")
var GRASS: int
var DIRT: int
var WATER: int
var WOOD: int
var RUG: int

var _checks: int = 0
var _failures: int = 0

func _ready() -> void:
	GRASS = CATALOG.terrain_id(&"grass")
	DIRT = CATALOG.terrain_id(&"dirt")
	WATER = CATALOG.terrain_id(&"water")
	WOOD = CATALOG.floor_id(&"wood")
	RUG = CATALOG.floor_id(&"rug")
	_types_are_named_and_numbered_by_the_catalog()
	_the_authors_art_is_used_and_its_layout_read()
	_commands_are_validated()
	_a_change_redraws_only_its_corners()
	_terrain_blends_and_lower_types_fill_under()
	_a_floor_never_bleeds_past_its_cells()
	_walls_join_their_neighbours()
	_a_floor_runs_under_its_walls()
	_a_building_owns_its_footprint()
	_footprints_touch_but_never_overlap()
	_walls_stay_inside_their_own_building()
	_a_door_goes_into_a_straight_wall()
	_a_door_toggles_and_is_removed()
	_rooms_need_walls_all_round_and_a_door()
	_walls_split_and_merge_rooms()
	_touching_buildings_keep_their_own_rooms()
	_roofs_cover_rooms_and_their_walls()
	_furniture_covers_its_cells()
	_attachments_need_a_host_with_a_free_slot()
	_a_piece_turns_when_placed()
	_rooms_take_their_type_from_their_furniture()
	_a_house_built_by_hand()
	_the_preview_predicts_the_build_system()
	_a_turn_moves_cells_round_the_footprint()
	_a_house_is_saved_and_stamped_ten_times()
	_a_saved_town_reloads_intact()
	_every_shipped_building_stamps_in_every_turn()
	_measure()
	_measure_rooms()
	print("[town] %d/%d checks passed" % [_checks - _failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)

## A world with a grid, the build system and the tile sync, drawn once.
func _setup(size: Vector2i) -> Dictionary:
	var world := EcsWorld.new()
	world.add_singleton(EcsTownGrid.make(size.x, size.y, GRASS))
	world.add_singleton(EcsLifecycleSingleton.new())
	var root := Node.new()
	add_child(root)
	var tiles := Node.new()
	root.add_child(tiles)
	var entities := Node2D.new()
	root.add_child(entities)
	var build := EcsBuildCommandSystem.new(CATALOG, ENTITIES)
	var sync := EcsTileSyncSystem.new(tiles, CATALOG)
	var scheduler := EcsScheduler.new()
	# As main.gd: lifecycle first, so a building asked for last tick is born before build binds it.
	var rooms := EcsRoomDetectionSystem.new(CATALOG)
	scheduler.add(EcsLifecycleSystem.new(EcsEntityManager.new(entities), ENTITIES)).add(build) \
		.add(rooms).add(EcsRoofSystem.new(CATALOG)).add(sync)
	scheduler.run_all(world, 0.0)
	_sync_for_mask = sync
	return {"world": world, "grid": world.get_singleton(EcsTownGridSingleton), "build": build, "rooms": rooms,
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
		var house: Array[EcsBuildCommand] = [EcsBuildCommand.create_building(Rect2i(1, 1, 20, 20))]
		for k in 20:
			for cell in [Vector2i(1 + k, 1), Vector2i(1 + k, 20), Vector2i(1, 1 + k), Vector2i(20, 1 + k)]:
				house.append(_cmd(EcsBuildCommand.Kind.PLACE_WALL, cell, 1))
		_send(t, house)
		var house_usec := build.last_usec
		var house_sync := sync.last_usec
		_send(t, [])
		started = Time.get_ticks_usec()
		for i in 100:
			(t.scheduler as EcsScheduler).run_all(t.world, 0.0)
		var idle := float(Time.get_ticks_usec() - started) / 100.0
		print("[town] %dx%d: first draw %d ms; one cell: tile sync %.0f µs, command %.1f µs; a 20x20 building and its 80 walls: commands %d µs, tile sync %d µs; idle tick %.1f µs"
			% [side, side, full / 1000, float(per_change) / n, float(per_command) / n, house_usec, house_sync, idle])
		_check("an idle %d² grid redraws nothing" % side, sync.redrawn == 0)
		t.root.queue_free()

var _sync_for_mask: EcsTileSyncSystem

## Prints room recompute time after one wall changes, by building size.
func _measure_rooms() -> void:
	var t := _setup(Vector2i(128, 64))
	var line := ""
	var x := 1
	for side in [10, 20, 40]:
		_send(t, _box(Rect2i(x, 1, side, side), [Vector2i(x + 2, side)]))
		_send(t, [])
		var total := 0
		for k in 20:
			var kind := EcsBuildCommand.Kind.PLACE_WALL if k % 2 == 0 else EcsBuildCommand.Kind.REMOVE_STRUCTURE
			_send(t, [_cmd(kind, Vector2i(x + 3, 4), 1)])
			total += (t.rooms as EcsRoomDetectionSystem).last_usec
		line += "  %d²: %d µs" % [side, total / 20]
		x += side + 1
	print("[town] room recompute after one wall, by building size:%s" % line)
	t.root.queue_free()

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
	_check("it builds a layer per type from its def's tiles, in catalog order",
		names == ["Terrain_grass", "Terrain_dirt", "Terrain_sand", "Terrain_water",
			"Floor_wood", "Floor_stone", "Floor_road", "Floor_rug"])
	var main := MAIN.instantiate()
	_check("and the scene holds none: main.tscn's TilemapGroup is empty",
		main.get_node("World/TilemapGroup").get_child_count() == 0)
	main.free()
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
	_check("WoodFloor, a bare sheet, reads from its pixels as the table its painted peering bits gave",
		_same_layout(wood, EcsDualGrid.CORNER_ATLAS))
	var once := CATALOG.tiles(CATALOG.terrains[0]) == CATALOG.tiles(CATALOG.terrains[0])
	var started := Time.get_ticks_usec()
	for def in CATALOG.terrains + CATALOG.floors + CATALOG.roofs:
		EcsDualGrid.corner_layout(EcsDualGrid.make_tile_set(def.texture, def.tile_size).get_source(0))
	print("[town] measure: every dual-grid TileSet made from its sheet and read: %d µs" % (Time.get_ticks_usec() - started))
	_check("a def's TileSet is made once a run, then reused", once)
	var grass_set := sync.terrain_layers()[0].tile_set
	var grass := EcsDualGrid.corner_layout(grass_set.get_source(grass_set.get_source_id(0)))
	_check("the 16 px grass, read from transparency: diagonals at 3:2 and 4:2, 10 full variants",
		grass[EcsDualGrid.TL | EcsDualGrid.BR] == [Vector2i(3, 2)]
		and grass[EcsDualGrid.TR | EcsDualGrid.BL] == [Vector2i(4, 2)]
		and (grass[EcsDualGrid.FULL] as Array).size() == 10)
	_check("and draws it at 2x, from its 16 px tile size", sync.terrain_layers()[0].scale == Vector2(2, 2))
	var walls := sync.wall_layer().tile_set
	_check("WoodWall and BaseWall, bare sheets, read all 16 wall shapes, WoodWall as its painted table did",
		_same_layout(EcsDualGrid.side_layout(walls.get_source(CATALOG.wall(1).source_id)), EcsDualGrid.SIDE_ATLAS)
		and EcsDualGrid.side_layout(walls.get_source(CATALOG.wall(2).source_id)).size() == 16)
	var closed := walls.get_source(CATALOG.door(1).closed_source_id) as TileSetAtlasSource
	_check("a door's 48 px tiles are cut after its 8 px margin, and both doors share the open sheet's one source",
		closed.get_tile_texture_region(Vector2i(1, 0)) == Rect2i(56, 8, 48, 48) and closed.get_tiles_count() == 2
		and CATALOG.door(1).open_source_id == CATALOG.door(2).open_source_id
		and CATALOG.door(1).closed_source_id != CATALOG.door(2).closed_source_id)
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
## A floor runs under its walls to their middle, so no ground shows between floor and wall;
## outside the walls it stops; a wall going redraws the floor around it.
func _a_floor_runs_under_its_walls() -> void:
	var t := _setup(Vector2i(10, 8))
	var sync := t.sync as EcsTileSyncSystem
	var plan := _box(Rect2i(2, 2, 5, 4), [Vector2i(4, 5)])
	for y in range(3, 5):
		for x in range(3, 6):
			plan.append(_cmd(EcsBuildCommand.Kind.SET_FLOOR, Vector2i(x, y), WOOD))
	_send(t, plan)
	_send(t, [])
	var wood := sync.floor_layers()[0]
	# Render tile (3, 3) is on wall (2, 2)'s corner and floor (3, 3); (4, 5) on the door's inner side.
	_check("by a wall the floor fills whole tiles: the wall's quarters take the floor beside them",
		sync.mask_at(wood, Vector2i(3, 3)) == EcsDualGrid.FULL and sync.mask_at(wood, Vector2i(6, 3)) == EcsDualGrid.FULL
		and sync.mask_at(wood, Vector2i(4, 5)) == EcsDualGrid.FULL)
	_check("and outside the walls, past their middle, it stops", sync.mask_at(wood, Vector2i(2, 2)) == 0
		and sync.mask_at(wood, Vector2i(7, 4)) == 0 and sync.mask_at(wood, Vector2i(4, 6)) == 0)
	# Floor laid first, then the wall built over it: the floor still stops at the wall's middle.
	_send(t, [_cmd(EcsBuildCommand.Kind.SET_FLOOR, Vector2i(2, 3), WOOD), _cmd(EcsBuildCommand.Kind.SET_FLOOR, Vector2i(2, 4), WOOD)])
	_check("floored before the wall went up, it still stops at the wall's middle, not past it outside",
		sync.mask_at(wood, Vector2i(2, 4)) == 0 and sync.mask_at(wood, Vector2i(3, 4)) == EcsDualGrid.FULL)
	_send(t, [_cmd(EcsBuildCommand.Kind.REMOVE_STRUCTURE, Vector2i(6, 3))])
	# The gap is bare ground now; the wall below it still takes the floor beside it.
	_check("a wall taken out redraws the floor's edge where it stood",
		sync.mask_at(wood, Vector2i(6, 4)) == EcsDualGrid.TL | EcsDualGrid.BL | EcsDualGrid.BR)
	t.root.queue_free()

func _walls_join_their_neighbours() -> void:
	var t := _setup(Vector2i(10, 10))
	var grid := t.grid as EcsTownGridSingleton
	var sync := t.sync as EcsTileSyncSystem
	var plan: Array[EcsBuildCommand] = [EcsBuildCommand.create_building(Rect2i(0, 0, 10, 10))]
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
		sync.wall_layer().get_cell_source_id(Vector2i(8, 8)) == CATALOG.wall(2).source_id and sync.wall_mask_at(Vector2i(8, 8)) == 0)
	_check("an unknown wall type, or a cell with an object, is refused",
		unknown.result == &"unknown_wall" and blocked.result == &"occupied")
	t.root.queue_free()

## A building asked for is born at the next lifecycle; its footprint is reserved at once,
## so walls in the same batch belong to it, and then carries its entity id.
func _a_building_owns_its_footprint() -> void:
	var t := _setup(Vector2i(16, 12))
	var grid := t.grid as EcsTownGridSingleton
	var world := t.world as EcsWorld
	var create := EcsBuildCommand.create_building(Rect2i(2, 2, 6, 5))
	var wall := _cmd(EcsBuildCommand.Kind.PLACE_WALL, Vector2i(2, 2), 1)
	_send(t, [create, wall])
	_check("a building is reserved at once, and a wall in the same batch is its",
		create.result == &"ok" and create.building < -1 and wall.result == &"ok"
		and grid.building_id[EcsTownGrid.index(grid, Vector2i(2, 2))] == create.building)
	_send(t, [])
	var ids := world.query([EcsBuildingComponent])
	var id: int = ids[0] if ids.size() == 1 else EcsWorld.NO_ENTITY
	var building := world.get_component(id, EcsBuildingComponent) as EcsBuildingComponent
	var owned := 0
	for owner in grid.building_id:
		if owner == id:
			owned += 1
	_check("next tick it is an entity with that footprint, on all 30 of its cells",
		building != null and building.footprint == Rect2i(2, 2, 6, 5) and owned == 30 and grid.pending.is_empty())
	_check("placed at its footprint's centre", (world.get_component(id, EcsPositionComponent) as EcsPositionComponent).position
		== Vector2(5, 4.5) * EcsTownGrid.CELL)
	var close := EcsBuildCommand.new()
	close.kind = EcsBuildCommand.Kind.CLOSE_BUILDING
	close.building = id
	var nothing := EcsBuildCommand.new()
	nothing.kind = EcsBuildCommand.Kind.CLOSE_BUILDING
	var overlay := EcsTownOverlay.new()
	t.root.add_child(overlay)
	var overlay_system := EcsTownOverlaySystem.new(overlay)
	overlay_system.run(world, 0.0)
	var open_before: bool = overlay.closed == [false]
	_send(t, [close, nothing])
	_check("closing it needs no room", building.closed and nothing.result == &"no_building")
	overlay_system.run(world, 0.0)
	_check("and the overlay shows it closed", open_before and overlay.closed == [true])
	t.root.queue_free()

func _footprints_touch_but_never_overlap() -> void:
	var t := _setup(Vector2i(16, 12))
	var a := EcsBuildCommand.create_building(Rect2i(1, 1, 5, 5))
	var touching := EcsBuildCommand.create_building(Rect2i(6, 1, 4, 5))
	var overlapping := EcsBuildCommand.create_building(Rect2i(5, 5, 3, 3))
	var outside := EcsBuildCommand.create_building(Rect2i(14, 10, 4, 4))
	_send(t, [a, touching, overlapping, outside])
	_check("a footprint touching another is allowed", a.result == &"ok" and touching.result == &"ok")
	_check("one overlapping is refused, even in the same batch", overlapping.result == &"overlaps")
	_check("one off the grid is refused", outside.result == &"out_of_bounds")
	t.root.queue_free()

## Walls go only inside a footprint, belong to it, and join only their own building's walls:
## two touching buildings' walls along the shared edge stay two walls.
func _walls_stay_inside_their_own_building() -> void:
	var t := _setup(Vector2i(16, 12))
	var grid := t.grid as EcsTownGridSingleton
	var sync := t.sync as EcsTileSyncSystem
	var left := EcsBuildCommand.create_building(Rect2i(1, 1, 4, 4))
	var right := EcsBuildCommand.create_building(Rect2i(5, 1, 4, 4))
	_send(t, [left, right])
	var plan: Array[EcsBuildCommand] = []
	for y in range(1, 5):
		plan.append(_cmd(EcsBuildCommand.Kind.PLACE_WALL, Vector2i(4, y), 1))
		plan.append(_cmd(EcsBuildCommand.Kind.PLACE_WALL, Vector2i(5, y), 1))
	var outside := _cmd(EcsBuildCommand.Kind.PLACE_WALL, Vector2i(12, 8), 1)
	var wrong := _cmd(EcsBuildCommand.Kind.PLACE_WALL, Vector2i(6, 2), 1)
	wrong.building = left.building
	plan.append_array([outside, wrong])
	_send(t, plan)
	_check("a wall outside every footprint is refused", outside.result == &"outside_building")
	_check("a wall named for one building on another's cell is refused", wrong.result == &"not_its_building")
	_check("each side's walls are its own building's",
		grid.building_id[EcsTownGrid.index(grid, Vector2i(4, 2))] != grid.building_id[EcsTownGrid.index(grid, Vector2i(5, 2))])
	_check("and the two walls along the shared edge don't join each other",
		sync.wall_mask_at(Vector2i(4, 2)) == EcsDualGrid.TOP | EcsDualGrid.BOTTOM
		and sync.wall_mask_at(Vector2i(5, 2)) == EcsDualGrid.TOP | EcsDualGrid.BOTTOM)
	t.root.queue_free()

## A building with a wall run along the top, x 2..8 at y 2, and down the left, y 2..7 at x 2.
func _walled(t: Dictionary) -> EcsBuildCommand:
	var create := EcsBuildCommand.create_building(Rect2i(2, 2, 7, 6))
	var plan: Array[EcsBuildCommand] = [create]
	for x in range(2, 9):
		plan.append(_cmd(EcsBuildCommand.Kind.PLACE_WALL, Vector2i(x, 2), 1))
	for y in range(3, 8):
		plan.append(_cmd(EcsBuildCommand.Kind.PLACE_WALL, Vector2i(2, y), 1))
	_send(t, plan)
	return create

## Doors go only into a straight run of their building's walls; the door is an entity
## bound to its cell, a child of its building; it lies along its wall and the walls
## beside it end in posts.
func _a_door_goes_into_a_straight_wall() -> void:
	var t := _setup(Vector2i(12, 10))
	var grid := t.grid as EcsTownGridSingleton
	var world := t.world as EcsWorld
	var sync := t.sync as EcsTileSyncSystem
	_walled(t)
	var across := _cmd(EcsBuildCommand.Kind.PLACE_DOOR, Vector2i(5, 2), 1)
	var down := _cmd(EcsBuildCommand.Kind.PLACE_DOOR, Vector2i(2, 5), 2)
	var corner := _cmd(EcsBuildCommand.Kind.PLACE_DOOR, Vector2i(2, 2), 1)
	var end := _cmd(EcsBuildCommand.Kind.PLACE_DOOR, Vector2i(8, 2), 1)
	var floor_cell := _cmd(EcsBuildCommand.Kind.PLACE_DOOR, Vector2i(5, 5), 1)
	var unknown := _cmd(EcsBuildCommand.Kind.PLACE_DOOR, Vector2i(6, 2), 99)
	_send(t, [across, down, corner, end, floor_cell, unknown])
	_check("a door goes into a straight wall, either way", across.result == &"ok" and down.result == &"ok")
	_check("not into a corner or a wall's end", corner.result == &"not_a_straight_wall" and end.result == &"not_a_straight_wall")
	_check("not where there is no wall, nor of an unknown type",
		floor_cell.result == &"not_on_wall" and unknown.result == &"unknown_door")
	var i := EcsTownGrid.index(grid, Vector2i(5, 2))
	_check("its cell is a door at once, holding a token", grid.structure[i] == EcsTownGridSingleton.DOOR
		and grid.object_id[i] < EcsTownGridSingleton.NO_ID)
	_send(t, [])
	var id := grid.object_id[i]
	var place := world.get_component(id, EcsGridPositionComponent) as EcsGridPositionComponent if id > 0 else null
	var building := world.get_component(grid.building_id[i], EcsBuildingComponent) as EcsBuildingComponent
	_check("next tick the door is an entity on that cell, a child of its building",
		place != null and place.cell == Vector2i(5, 2) and world.has(id, EcsDoorComponent)
		and building.children.has(id))
	_check("drawn closed, along its wall: your wood door across, the stone one down",
		sync.door_tile_at(Vector2i(5, 2)) == [CATALOG.door(1).closed_source_id, Vector2i(0, 0)]
		and sync.door_tile_at(Vector2i(2, 5)) == [CATALOG.door(2).closed_source_id, Vector2i(1, 0)])
	_check("and the walls beside it end in posts",
		sync.wall_mask_at(Vector2i(4, 2)) == EcsDualGrid.LEFT and sync.wall_mask_at(Vector2i(6, 2)) == EcsDualGrid.RIGHT)
	var over := _cmd(EcsBuildCommand.Kind.PLACE_WALL, Vector2i(5, 2), 1)
	_send(t, [over])
	_check("a wall can't be placed over a door", over.result == &"occupied")
	t.root.queue_free()

func _a_door_toggles_and_is_removed() -> void:
	var t := _setup(Vector2i(12, 10))
	var grid := t.grid as EcsTownGridSingleton
	var world := t.world as EcsWorld
	var sync := t.sync as EcsTileSyncSystem
	_walled(t)
	var early := _cmd(EcsBuildCommand.Kind.TOGGLE_DOOR, Vector2i(5, 2))
	_send(t, [_cmd(EcsBuildCommand.Kind.PLACE_DOOR, Vector2i(5, 2), 1), early])
	_check("a door not yet born can't be opened", early.result == &"not_built_yet")
	_send(t, [])
	var id := grid.object_id[EcsTownGrid.index(grid, Vector2i(5, 2))]
	var door := world.get_component(id, EcsDoorComponent) as EcsDoorComponent
	var wall := _cmd(EcsBuildCommand.Kind.TOGGLE_DOOR, Vector2i(4, 2))
	_send(t, [_cmd(EcsBuildCommand.Kind.TOGGLE_DOOR, Vector2i(5, 2)), wall])
	_check("toggling opens it: an open tile swapped in, one cell redrawn",
		door.is_open and sync.door_tile_at(Vector2i(5, 2)) == [CATALOG.door(1).open_source_id, Vector2i(2, 0)] and sync.redrawn == 1)
	_check("toggling a wall is refused", wall.result == &"not_a_door")
	_send(t, [_cmd(EcsBuildCommand.Kind.TOGGLE_DOOR, Vector2i(5, 2))])
	_check("and again closes it", not door.is_open and sync.door_tile_at(Vector2i(5, 2)) == [CATALOG.door(1).closed_source_id, Vector2i(0, 0)])
	_send(t, [_cmd(EcsBuildCommand.Kind.REMOVE_STRUCTURE, Vector2i(5, 2))])
	var dying := world.get_component(id, EcsDyingFlag) as EcsDyingFlag
	var building := world.get_component(grid.building_id[EcsTownGrid.index(grid, Vector2i(5, 2))], EcsBuildingComponent) as EcsBuildingComponent
	_check("removing it frees the cell and the door dies, cause removed",
		grid.object_id[EcsTownGrid.index(grid, Vector2i(5, 2))] == EcsTownGridSingleton.NO_ID
		and dying != null and dying.cause == EcsDyingFlag.REMOVED and not building.children.has(id))
	_send(t, [])
	_check("next tick it is gone, and the walls either side end at the gap",
		not world.is_alive(id) and sync.door_tile_at(Vector2i(5, 2)).is_empty()
		and sync.wall_mask_at(Vector2i(4, 2)) == EcsDualGrid.LEFT)
	_send(t, [_cmd(EcsBuildCommand.Kind.PLACE_WALL, Vector2i(5, 2), 1)])
	var doors_before := world.query([EcsDoorComponent]).size()
	_send(t, [_cmd(EcsBuildCommand.Kind.PLACE_DOOR, Vector2i(5, 2), 1), _cmd(EcsBuildCommand.Kind.REMOVE_STRUCTURE, Vector2i(5, 2))])
	_send(t, [])
	_send(t, [])
	_check("a door removed before it was born doesn't outlive its cell",
		world.query([EcsDoorComponent]).size() == doors_before and grid.pending.is_empty())
	t.root.queue_free()

## Commands for a building on `rect` walled all round, less `gaps`, with doors on `doors`.
func _box(rect: Rect2i, doors: Array = [], gaps: Array = []) -> Array[EcsBuildCommand]:
	var plan: Array[EcsBuildCommand] = [EcsBuildCommand.create_building(rect)]
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var edge := x == rect.position.x or y == rect.position.y or x == rect.end.x - 1 or y == rect.end.y - 1
			if edge and not gaps.has(Vector2i(x, y)):
				plan.append(_cmd(EcsBuildCommand.Kind.PLACE_WALL, Vector2i(x, y), 1))
	for door in doors:
		plan.append(_cmd(EcsBuildCommand.Kind.PLACE_DOOR, door, 1))
	return plan

## The building owning `cell`, by its grid id.
func _building_at(t: Dictionary, cell: Vector2i) -> EcsBuildingComponent:
	var grid := t.grid as EcsTownGridSingleton
	return (t.world as EcsWorld).get_component(grid.building_id[EcsTownGrid.index(grid, cell)], EcsBuildingComponent) as EcsBuildingComponent

func _room_at(t: Dictionary, cell: Vector2i) -> int:
	var grid := t.grid as EcsTownGridSingleton
	return grid.room_id[EcsTownGrid.index(grid, cell)]

## Enclosed with a door is a room; with a gap it is open and nothing is kept; with no door
## it is sealed; a corner missing only diagonally still seals.
func _rooms_need_walls_all_round_and_a_door() -> void:
	var t := _setup(Vector2i(40, 12))
	var plan: Array[EcsBuildCommand] = []
	plan.append_array(_box(Rect2i(1, 1, 6, 5), [Vector2i(3, 5)]))
	plan.append_array(_box(Rect2i(9, 1, 6, 5), [], [Vector2i(11, 1)]))
	plan.append_array(_box(Rect2i(17, 1, 6, 5)))
	plan.append_array(_box(Rect2i(25, 1, 6, 5), [Vector2i(27, 5)], [Vector2i(30, 5)]))
	_send(t, plan)
	_send(t, [])
	var room: Array = _building_at(t, Vector2i(1, 1)).rooms
	_check("walls all round with a door make a room: 12 cells, the door on its boundary",
		room.size() == 1 and not room[0]["sealed"] and (room[0]["cells"] as Array).size() == 12
		and room[0]["door_cells"] == [Vector2i(3, 5)] and _room_at(t, Vector2i(3, 3)) == room[0]["id"])
	_check("a gap in the wall leaves it open: no room kept",
		_building_at(t, Vector2i(9, 1)).rooms.is_empty() and _room_at(t, Vector2i(11, 3)) == EcsTownGridSingleton.NO_ID)
	var sealed: Array = _building_at(t, Vector2i(17, 1)).rooms
	_check("enclosed with no door is sealed, not a room",
		sealed.size() == 1 and sealed[0]["sealed"] and _room_at(t, Vector2i(19, 3)) == EcsTownGridSingleton.NO_ID)
	var diagonal: Array = _building_at(t, Vector2i(25, 1)).rooms
	_check("a corner missing only diagonally still encloses it",
		diagonal.size() == 1 and not diagonal[0]["sealed"] and (diagonal[0]["cells"] as Array).size() == 12)
	t.root.queue_free()

## A wall across a room splits it in two, each with its own door; removing it merges them.
func _walls_split_and_merge_rooms() -> void:
	var t := _setup(Vector2i(16, 12))
	_send(t, _box(Rect2i(1, 1, 9, 5), [Vector2i(3, 5), Vector2i(7, 5)]))
	_send(t, [])
	var building := _building_at(t, Vector2i(1, 1))
	_check("one room before the split", building.rooms.size() == 1)
	var split: Array[EcsBuildCommand] = []
	for y in range(2, 5):
		split.append(_cmd(EcsBuildCommand.Kind.PLACE_WALL, Vector2i(5, y), 1))
	_send(t, split)
	_check("a wall across it makes two rooms, each with its own door",
		building.rooms.size() == 2 and _room_at(t, Vector2i(3, 3)) != _room_at(t, Vector2i(7, 3))
		and not building.rooms[0]["sealed"] and not building.rooms[1]["sealed"])
	_send(t, [_cmd(EcsBuildCommand.Kind.REMOVE_STRUCTURE, Vector2i(5, 3))])
	_check("removing a wall of it merges them again", building.rooms.size() == 1
		and _room_at(t, Vector2i(3, 3)) == _room_at(t, Vector2i(7, 3)))
	_check("only the changed building is recomputed", (t.rooms as EcsRoomDetectionSystem).recomputed == 1)
	t.root.queue_free()

func _touching_buildings_keep_their_own_rooms() -> void:
	var t := _setup(Vector2i(16, 12))
	var plan: Array[EcsBuildCommand] = []
	plan.append_array(_box(Rect2i(1, 1, 5, 5), [Vector2i(3, 5)]))
	plan.append_array(_box(Rect2i(6, 1, 5, 5), [Vector2i(8, 5)]))
	_send(t, plan)
	_send(t, [])
	var left := _building_at(t, Vector2i(1, 1))
	var right := _building_at(t, Vector2i(6, 1))
	var inside := true
	for room: Dictionary in right.rooms:
		for cell: Vector2i in room["cells"]:
			if not right.footprint.has_point(cell):
				inside = false
	_check("two touching buildings each have their own room, inside their own footprint",
		left.rooms.size() == 1 and right.rooms.size() == 1 and left.rooms[0]["id"] != right.rooms[0]["id"] and inside)
	t.root.queue_free()

func _roofs_cover_rooms_and_their_walls() -> void:
	var t := _setup(Vector2i(16, 12))
	var grid := t.grid as EcsTownGridSingleton
	var sync := t.sync as EcsTileSyncSystem
	_send(t, _box(Rect2i(1, 1, 6, 5), [Vector2i(3, 5)]))
	_send(t, [])
	var roofed := 0
	for v in grid.roof:
		if v != 0:
			roofed += 1
	_check("a room is roofed with its walls and door: the whole 6x5 house", roofed == 30)
	_check("and drawn on the roof layer", not sync.roof_layers()[0].get_used_cells().is_empty())
	_send(t, [_cmd(EcsBuildCommand.Kind.REMOVE_STRUCTURE, Vector2i(1, 3))])
	roofed = 0
	for v in grid.roof:
		if v != 0:
			roofed += 1
	_check("opening the wall takes the roof off", roofed == 0 and sync.roof_layers()[0].get_used_cells().is_empty())
	t.root.queue_free()

func _obj(cell: Vector2i, blueprint: StringName) -> EcsBuildCommand:
	return EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, cell, blueprint)

func _att(cell: Vector2i, blueprint: StringName) -> EcsBuildCommand:
	return EcsBuildCommand.place(EcsBuildCommand.Kind.ATTACH, cell, blueprint)

func _object_at(t: Dictionary, cell: Vector2i) -> int:
	var grid := t.grid as EcsTownGridSingleton
	return grid.object_id[EcsTownGrid.index(grid, cell)]

## Furniture covers every cell of its size and draws its slice on each; it goes only on free
## cells, inside one building or none; plants never on a floor.
func _furniture_covers_its_cells() -> void:
	var t := _setup(Vector2i(20, 12))
	var world := t.world as EcsWorld
	var sync := t.sync as EcsTileSyncSystem
	var plan := _box(Rect2i(1, 1, 8, 6), [Vector2i(3, 6)])
	var bed := _obj(Vector2i(2, 2), &"bed")
	var on_bed := _obj(Vector2i(2, 3), &"chair")
	var on_wall := _obj(Vector2i(1, 3), &"chair")
	plan.append(EcsBuildCommand.create_building(Rect2i(11, 8, 3, 3)))
	var straddle := _obj(Vector2i(13, 9), &"long_table")
	var field := _obj(Vector2i(12, 3), &"sawmill")
	var unknown := _obj(Vector2i(14, 8), &"dragon")
	plan.append_array([bed, on_bed, on_wall, straddle, field, unknown])
	for x in range(5, 8):
		plan.append(_cmd(EcsBuildCommand.Kind.SET_FLOOR, Vector2i(x, 3), 1))
	var on_floor := _obj(Vector2i(6, 3), &"bush")
	var grass := _obj(Vector2i(16, 8), &"tree")
	plan.append_array([on_floor, grass])
	_send(t, plan)
	_send(t, [])
	_check("furniture on free cells is placed, indoors and out",
		bed.result == &"ok" and field.result == &"ok" and grass.result == &"ok")
	_check("not on other furniture or a wall, nor across a building's edge",
		on_bed.result == &"occupied" and on_wall.result == &"occupied" and straddle.result == &"straddles")
	_check("a plant never on a floor, and an unknown piece is refused",
		on_floor.result == &"plant_on_floor" and unknown.result == &"unknown_object")
	var id := _object_at(t, Vector2i(2, 2))
	_check("a bed is one entity on both its cells, a child of its building",
		id > 0 and _object_at(t, Vector2i(2, 3)) == id and world.has(id, EcsFurnitureComponent)
		and _building_at(t, Vector2i(1, 1)).children.has(id))
	var layer := (t.sync as EcsTileSyncSystem).furniture_layer()
	_check("each cell draws its slice: the bed's top and foot, the sawmill's four",
		layer.get_cell_atlas_coords(Vector2i(2, 2)) == Vector2i(0, 0) and layer.get_cell_atlas_coords(Vector2i(2, 3)) == Vector2i(0, 1)
		and layer.get_cell_atlas_coords(Vector2i(13, 4)) == Vector2i(1, 3))
	var sawmill := _object_at(t, Vector2i(12, 3))
	_check("a sawmill in a field belongs to no building", sawmill > 0
		and (t.grid as EcsTownGridSingleton).building_id[EcsTownGrid.index(t.grid, Vector2i(12, 3))] == EcsTownGridSingleton.NO_ID)
	_send(t, [_cmd(EcsBuildCommand.Kind.REMOVE_OBJECT, Vector2i(2, 3))])
	_check("removing it by any of its cells frees all of them",
		_object_at(t, Vector2i(2, 2)) == EcsTownGridSingleton.NO_ID and _object_at(t, Vector2i(2, 3)) == EcsTownGridSingleton.NO_ID
		and world.has(id, EcsDyingFlag) and layer.get_cell_source_id(Vector2i(2, 2)) == -1)
	t.root.queue_free()

## An attachment needs a host that takes it — a wall, or furniture that holds things —
## and a free slot; removing the host takes its attachments first.
## A turned piece covers its turned cells and draws, on each, the slice that turned there,
## with the tile flags for the turn; turned into a wall it is refused, and it is removed whole.
func _a_piece_turns_when_placed() -> void:
	var t := _setup(Vector2i(10, 10))
	var world := t.world as EcsWorld
	var grid := t.grid as EcsTownGridSingleton
	var sync := t.sync as EcsTileSyncSystem
	var bed := EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, Vector2i(2, 2), &"bed", 1)
	_send(t, [bed])
	_send(t, [])
	var id := _object_at(t, Vector2i(2, 2))
	var place := world.get_component(id, EcsGridPositionComponent) as EcsGridPositionComponent
	_check("a bed (1x2) turned once lies across two cells, 2x1", bed.result == &"ok" and id > 0
		and _object_at(t, Vector2i(3, 2)) == id and _object_at(t, Vector2i(2, 3)) == -1
		and place.size == Vector2i(2, 1) and place.turns == 1)
	var layer := sync.furniture_layer()
	var tile := world.get_component(id, EcsTileComponent) as EcsTileComponent
	var cw := TileSetAtlasSource.TRANSFORM_TRANSPOSE | TileSetAtlasSource.TRANSFORM_FLIP_H
	_check("its foot draws on the left, its head on the right, each tile turned clockwise",
		layer.get_cell_atlas_coords(Vector2i(2, 2)) == tile.atlas + Vector2i(0, 1)
		and layer.get_cell_atlas_coords(Vector2i(3, 2)) == tile.atlas
		and layer.get_cell_alternative_tile(Vector2i(2, 2)) == cw and layer.get_cell_alternative_tile(Vector2i(3, 2)) == cw)
	var flags := []
	for turns in 4:
		var chair := EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, Vector2i(6, 4 + turns), &"chair", turns)
		_send(t, [chair])
		_send(t, [])
		flags.append(layer.get_cell_alternative_tile(Vector2i(6, 4 + turns)))
	_check("each quarter turn draws with its own flags", flags == Array(EcsTileSyncSystem.TURN_FLAGS))
	_send(t, [EcsBuildCommand.create_building(Rect2i(7, 0, 3, 3)), _cmd(EcsBuildCommand.Kind.PLACE_WALL, Vector2i(9, 0), 1)])
	_send(t, [])
	var into_wall := EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, Vector2i(8, 0), &"bed", 1)
	var upright := EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, Vector2i(8, 0), &"bed", 0)
	var why := EcsBuildRules.refusal(world, grid, CATALOG, ENTITIES, into_wall)
	_send(t, [into_wall, upright])
	_check("turned into a wall it is refused, upright it fits", why == &"occupied"
		and into_wall.result == why and upright.result == &"ok")
	_send(t, [_cmd(EcsBuildCommand.Kind.REMOVE_OBJECT, Vector2i(3, 2))])
	_send(t, [])
	_check("removed by either cell, both are freed and drawn empty", _object_at(t, Vector2i(2, 2)) == -1
		and _object_at(t, Vector2i(3, 2)) == -1 and layer.get_cell_source_id(Vector2i(2, 2)) == -1)
	t.root.queue_free()

func _attachments_need_a_host_with_a_free_slot() -> void:
	var t := _setup(Vector2i(16, 12))
	var grid := t.grid as EcsTownGridSingleton
	var world := t.world as EcsWorld
	var plan := _box(Rect2i(1, 1, 8, 6), [Vector2i(3, 6)])
	plan.append(_obj(Vector2i(4, 3), &"table"))
	var candle := _att(Vector2i(4, 3), &"candle")
	var lamp := _att(Vector2i(1, 3), &"wall_lamp")
	var second := _att(Vector2i(4, 3), &"mug")
	var candle_on_wall := _att(Vector2i(1, 4), &"candle")
	var lamp_on_table := _att(Vector2i(6, 3), &"wall_lamp")
	plan.append(_obj(Vector2i(6, 3), &"stove"))
	plan.append(_obj(Vector2i(6, 4), &"barrel"))
	var on_barrel := _att(Vector2i(6, 4), &"mug")
	var on_floor := _att(Vector2i(5, 5), &"mug")
	plan.append_array([candle, lamp, second, candle_on_wall, lamp_on_table, on_barrel, on_floor])
	_send(t, plan)
	_send(t, [])
	_check("a candle on a table placed in the same batch, a lamp on a wall",
		candle.result == &"ok" and lamp.result == &"ok")
	_check("one per slot; a candle won't hang on a wall, a wall lamp won't stand on a stove",
		second.result == &"slot_taken" and candle_on_wall.result == &"not_for_this_host"
		and lamp_on_table.result == &"not_for_this_host")
	_check("a barrel holds nothing, and bare floor is no host", on_barrel.result == &"no_host" and on_floor.result == &"no_host")
	var candle_id := grid.attachment_id[EcsTownGrid.index(grid, Vector2i(4, 3))]
	var on := world.get_component(candle_id, EcsAttachedToComponent) as EcsAttachedToComponent
	_check("the candle knows its table", on != null and on.host_kind == EcsAttachedToComponent.HostKind.ENTITY
		and on.host_id == _object_at(t, Vector2i(4, 3)))
	var layer := (t.sync as EcsTileSyncSystem).attachment_layer()
	_check("both are drawn", layer.get_cell_atlas_coords(Vector2i(4, 3)) == Vector2i(1, 0)
		and layer.get_cell_atlas_coords(Vector2i(1, 3)) == Vector2i(0, 0))
	var lamp_id := grid.attachment_id[EcsTownGrid.index(grid, Vector2i(1, 3))]
	_send(t, [_cmd(EcsBuildCommand.Kind.REMOVE_OBJECT, Vector2i(4, 3)), _cmd(EcsBuildCommand.Kind.REMOVE_STRUCTURE, Vector2i(1, 3))])
	_check("removing the table takes its candle, removing the wall its lamp",
		world.has(candle_id, EcsDyingFlag) and world.has(lamp_id, EcsDyingFlag)
		and grid.attachment_id[EcsTownGrid.index(grid, Vector2i(4, 3))] == EcsTownGridSingleton.NO_ID
		and layer.get_cell_source_id(Vector2i(4, 3)) == -1)
	t.root.queue_free()

func _rooms_take_their_type_from_their_furniture() -> void:
	var t := _setup(Vector2i(16, 12))
	var plan := _box(Rect2i(1, 1, 9, 6), [Vector2i(3, 6), Vector2i(7, 6)])
	for y in range(2, 6):
		plan.append(_cmd(EcsBuildCommand.Kind.PLACE_WALL, Vector2i(5, y), 1))
	plan.append(_obj(Vector2i(2, 2), &"bed"))
	plan.append(_obj(Vector2i(7, 2), &"stove"))
	_send(t, plan)
	_send(t, [])
	_send(t, [])
	var type_at := func(cell: Vector2i) -> StringName:
		for room: Dictionary in _building_at(t, Vector2i(1, 1)).rooms:
			if (room["cells"] as Array).has(cell):
				return room["type"]
		return &"?"
	_check("a bed makes a bedroom, a stove a kitchen", type_at.call(Vector2i(3, 3)) == &"bedroom"
		and type_at.call(Vector2i(7, 4)) == &"kitchen")
	_send(t, [_obj(Vector2i(4, 4), &"table")])
	_send(t, [])
	_check("the bed outranks a table", type_at.call(Vector2i(3, 3)) == &"bedroom")
	_send(t, [_cmd(EcsBuildCommand.Kind.REMOVE_OBJECT, Vector2i(2, 2))])
	_send(t, [])
	_check("without the bed it is a dining room", type_at.call(Vector2i(3, 3)) == &"dining")
	_send(t, [_cmd(EcsBuildCommand.Kind.REMOVE_OBJECT, Vector2i(4, 4))])
	_send(t, [])
	_check("and empty, no type", type_at.call(Vector2i(3, 3)) == &"")
	t.root.queue_free()

## The brief's step 5: a house built entirely by hand — walls, a door, a floor, a bed, a
## table with a lamp on it — and its room typed correctly.
func _a_house_built_by_hand() -> void:
	var t := _setup(Vector2i(16, 12))
	var grid := t.grid as EcsTownGridSingleton
	var plan := _box(Rect2i(2, 2, 7, 6), [Vector2i(5, 7)])
	for y in range(3, 7):
		for x in range(3, 8):
			plan.append(_cmd(EcsBuildCommand.Kind.SET_FLOOR, Vector2i(x, y), 1))
	plan.append(_obj(Vector2i(3, 3), &"bed"))
	plan.append(_obj(Vector2i(6, 4), &"table"))
	plan.append(_att(Vector2i(6, 4), &"candle"))
	var all_ok := func(commands: Array[EcsBuildCommand]) -> bool:
		for command in commands:
			if command.result != &"ok":
				return false
		return true
	_send(t, plan)
	_send(t, [])
	_send(t, [])
	var rooms: Array = _building_at(t, Vector2i(2, 2)).rooms
	_check("built by hand in one batch, every command accepted", all_ok.call(plan))
	_check("one room, a bedroom, with a lamp on its table", rooms.size() == 1 and rooms[0]["type"] == &"bedroom"
		and grid.attachment_id[EcsTownGrid.index(grid, Vector2i(6, 4))] > 0)
	t.root.queue_free()

## Defs are named; the catalog numbers each list in order, with no number written by hand.
func _types_are_named_and_numbered_by_the_catalog() -> void:
	var unique := true
	var in_order := true
	for list: Array in [CATALOG.terrains, CATALOG.floors, CATALOG.walls, CATALOG.doors, CATALOG.roofs]:
		var seen: Dictionary = {}
		for k in list.size():
			if seen.has(list[k].key) or list[k].key == &"":
				unique = false
			seen[list[k].key] = true
			if list[k].id != k + 1:
				in_order = false
	_check("every def has its own key in its list", unique)
	_check("and the catalog numbers each list 1, 2, 3 in order", in_order)
	_check("a type is found by its name", CATALOG.terrain(CATALOG.terrain_id(&"sand")).key == &"sand"
		and CATALOG.wall_id(&"stone") == 2 and CATALOG.door_id(&"nothing") == 0)

## The placement preview asks EcsBuildRules; the build system applies with the same rules,
## so a preview's verdict is the command's result, refused or not.
func _the_preview_predicts_the_build_system() -> void:
	var t := _setup(Vector2i(16, 12))
	var grid := t.grid as EcsTownGridSingleton
	var world := t.world as EcsWorld
	var plan := _box(Rect2i(1, 1, 8, 6), [Vector2i(3, 6)])
	plan.append(_obj(Vector2i(4, 3), &"table"))
	_send(t, plan)
	_send(t, [])
	var tries: Array[EcsBuildCommand] = [
		_obj(Vector2i(2, 2), &"bed"), _obj(Vector2i(1, 3), &"chair"), _obj(Vector2i(4, 3), &"chair"),
		_att(Vector2i(4, 3), &"candle"), _att(Vector2i(1, 2), &"candle"), _att(Vector2i(5, 4), &"mug"),
		_cmd(EcsBuildCommand.Kind.PLACE_DOOR, Vector2i(8, 3), 1), _cmd(EcsBuildCommand.Kind.PLACE_DOOR, Vector2i(1, 1), 1),
		_cmd(EcsBuildCommand.Kind.PLACE_WALL, Vector2i(12, 8), 1), _cmd(EcsBuildCommand.Kind.TOGGLE_DOOR, Vector2i(3, 6)),
		_cmd(EcsBuildCommand.Kind.TOGGLE_DOOR, Vector2i(4, 4)), EcsBuildCommand.create_building(Rect2i(6, 4, 4, 4)),
	]
	var agree := true
	var refused := 0
	for command in tries:
		var predicted := EcsBuildRules.refusal(world, grid, CATALOG, ENTITIES, command)
		_send(t, [command])
		var actual := &"" if command.result == &"ok" else command.result
		if predicted != actual:
			agree = false
			print("[town]   predicted %s, got %s" % [predicted, actual])
		if actual != &"":
			refused += 1
	_check("for %d commands, %d refused, the preview's verdict is the result every time" % [tries.size(), refused], agree)
	t.root.queue_free()

## Two rooms through an inner door: a bedroom and a kitchen, a lamp on the wall, a candle on
## the long table. Settled, so every entity is born and every room found.
func _two_room_house(t: Dictionary, at: Vector2i) -> Array[EcsBuildCommand]:
	var plan := _box(Rect2i(at, Vector2i(9, 6)), [at + Vector2i(2, 5)])
	for y in range(1, 5):
		plan.append(_cmd(EcsBuildCommand.Kind.PLACE_WALL, at + Vector2i(4, y), 1))
		for x in range(1, 8):
			if x != 4:
				plan.append(_cmd(EcsBuildCommand.Kind.SET_FLOOR, at + Vector2i(x, y), WOOD))
	plan.append(_cmd(EcsBuildCommand.Kind.PLACE_DOOR, at + Vector2i(4, 2), 1))
	plan.append(_obj(at + Vector2i(1, 1), &"bed"))
	plan.append(_obj(at + Vector2i(7, 1), &"stove"))
	plan.append(_obj(at + Vector2i(5, 3), &"long_table"))
	plan.append(_att(at + Vector2i(6, 3), &"candle"))
	plan.append(_att(at + Vector2i(6, 0), &"wall_lamp"))
	_settle(t, plan)
	return plan

func _settle(t: Dictionary, plan: Array[EcsBuildCommand]) -> void:
	_send(t, plan)
	_send(t, [])
	_send(t, [])

func _all_ok(plan: Array[EcsBuildCommand]) -> bool:
	for command in plan:
		if command.result != &"ok":
			return false
	return true

## A building's rooms as comparable data: each room's type and size, sorted.
func _rooms_of(t: Dictionary, building: EcsBuildingComponent) -> Array:
	var out: Array = []
	for room: Dictionary in building.rooms:
		out.append("%s:%d:%d" % [room["type"], (room["cells"] as Array).size(), (room["door_cells"] as Array).size()])
	out.sort()
	return out

## Four quarter turns are none; a turned cell keeps its place relative to the footprint.
func _a_turn_moves_cells_round_the_footprint() -> void:
	var size := Vector2i(3, 2)
	_check("one turn clockwise takes the top-left to the top-right of the turned footprint",
		EcsTownGrid.turn(Vector2i.ZERO, size, 1) == Vector2i(1, 0)
		and EcsTownGrid.turn(Vector2i(2, 1), size, 1) == Vector2i(0, 2))
	var back := true
	for y in size.y:
		for x in size.x:
			back = back and EcsTownGrid.turn(Vector2i(x, y), size, 4) == Vector2i(x, y)
	var rect := EcsTownGrid.turn_rect(Rect2i(0, 0, 2, 1), size, 1)
	_check("four turns are none, and a 2x1 rect turns to 1x2", back and rect == Rect2i(1, 0, 1, 2))

## The brief's test: one house built by hand, saved as a def, stamped ten times in all four
## turns, every copy with the same rooms.
func _a_house_is_saved_and_stamped_ten_times() -> void:
	var t := _setup(Vector2i(64, 48))
	var world := t.world as EcsWorld
	var grid := t.grid as EcsTownGridSingleton
	var by_hand := _two_room_house(t, Vector2i(1, 1))
	var original := _building_at(t, Vector2i(1, 1))
	var want := _rooms_of(t, original)
	_check("the house by hand: every command accepted, a bedroom and a kitchen",
		_all_ok(by_hand) and want.size() == 2 and str(want).contains("bedroom") and str(want).contains("kitchen"))
	var def := EcsBuildingStamp.capture(world, grid, CATALOG, grid.building_id[EcsTownGrid.index(grid, Vector2i(1, 1))], &"cottage")
	_check("its def holds its walls, door cells, floors, pieces and attachments by key",
		def.size == Vector2i(9, 6) and def.walls.size() == 26 - 1 + 4 - 1 and def.doors.size() == 2
		and def.floors.size() == 24 and def.objects.size() == 3 and def.attachments.size() == 2
		and def.walls.values().has(&"wood") and def.objects.values().has(&"long_table"))
	var plan: Array[EcsBuildCommand] = []
	var spots: Array[Vector2i] = []
	for k in 10:
		var at := Vector2i(12 + (k % 5) * 10, 1 + (k / 5) * 11)
		spots.append(at)
		plan.append_array(EcsBuildingStamp.commands(def, CATALOG, ENTITIES, at, k))
	_send(t, plan)
	print("[town] measure: ten stamps, %d commands: applied in %d µs, tile sync %d µs, on the tick sent" % [plan.size(),
		(t.build as EcsBuildCommandSystem).last_usec, (t.sync as EcsTileSyncSystem).last_usec])
	_send(t, [])
	_send(t, [])
	var same := true
	var failed: Array = []
	for k in 10:
		var copy := _building_at(t, spots[k])
		if copy == null or _rooms_of(t, copy) != want or copy.footprint.size != EcsBuildingStamp.turned_size(def, k):
			same = false
			failed.append(k)
	_check("stamped ten times, turned 0-3 quarter turns, every command accepted", _all_ok(plan))
	_check("every copy has the same rooms, of the same types and sizes%s" % ("" if same else " (failed %s)" % [failed]), same)
	var lamps := world.query([EcsAttachedToComponent]).size()
	_check("and every copy kept its lamp and its candle", lamps == 2 * 11)
	t.root.queue_free()

## A saved world, loaded into a fresh one, has the same grid and the same buildings.
func _a_saved_town_reloads_intact() -> void:
	var t := _setup(Vector2i(40, 24))
	var world := t.world as EcsWorld
	var grid := t.grid as EcsTownGridSingleton
	_two_room_house(t, Vector2i(2, 2))
	var def := EcsBuildingStamp.capture(world, grid, CATALOG, grid.building_id[EcsTownGrid.index(grid, Vector2i(2, 2))])
	var plan := EcsBuildingStamp.commands(def, CATALOG, ENTITIES, Vector2i(14, 2), 1)
	plan.append(_cmd(EcsBuildCommand.Kind.SET_TERRAIN, Vector2i(30, 20), WATER))
	plan.append(_cmd(EcsBuildCommand.Kind.SET_FLOOR, Vector2i(25, 18), CATALOG.floor_id(&"road")))
	plan.append(_obj(Vector2i(32, 4), &"tree"))
	plan.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, Vector2i(34, 8), &"long_table", 1))
	var closed := EcsBuildCommand.new()
	closed.kind = EcsBuildCommand.Kind.CLOSE_BUILDING
	_settle(t, plan)
	closed.building = grid.building_id[EcsTownGrid.index(grid, Vector2i(2, 2))]
	_settle(t, [closed])
	var path := EcsTownSave.SAVE_DIR + "town_test.tres"
	DirAccess.make_dir_recursive_absolute(EcsTownSave.SAVE_DIR)
	var saved := ResourceSaver.save(EcsTownSave.capture(world, grid, CATALOG), path)
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as EcsTownSave
	_check("the town is saved to a file and read back", saved == OK and loaded != null and loaded.buildings.size() == 2)
	var u := _setup(loaded.size)
	var load_plan := loaded.commands(CATALOG, ENTITIES, GRASS)
	_settle(u, load_plan)
	var grid2 := u.grid as EcsTownGridSingleton
	var cells_same := grid2.terrain == grid.terrain and grid2.floor == grid.floor \
		and grid2.structure == grid.structure and grid2.wall_type == grid.wall_type and grid2.roof == grid.roof
	for i in grid.width * grid.height:
		cells_same = cells_same and (grid.object_id[i] == -1) == (grid2.object_id[i] == -1) \
			and (grid.attachment_id[i] == -1) == (grid2.attachment_id[i] == -1) \
			and (grid.building_id[i] == -1) == (grid2.building_id[i] == -1) and (grid.room_id[i] == -1) == (grid2.room_id[i] == -1)
	_check("reloaded, every command accepted, and every cell as it was", _all_ok(load_plan) and cells_same)
	var intact := true
	for at: Vector2i in [Vector2i(2, 2), Vector2i(14, 2)]:
		var a := _building_at(t, at)
		var b := _building_at(u, at)
		intact = intact and b != null and a.footprint == b.footprint and a.closed == b.closed \
			and _rooms_of(t, a) == _rooms_of(u, b) and a.children.size() == b.children.size()
	_check("its buildings intact: footprints, closed, rooms and pieces", intact)
	DirAccess.remove_absolute(path)
	t.root.queue_free()
	u.root.queue_free()

## The defs in defs/buildings/ build clean in all four turns, with the same rooms each time:
## a piece that can't keep its turned place finds another without taking a neighbour's.
func _every_shipped_building_stamps_in_every_turn() -> void:
	var dir := "res://10. Town Generator/defs/buildings/"
	var files := ResourceLoader.list_directory(dir)
	var clean := not files.is_empty()
	var bad: Array = []
	for file in files:
		var def := load(dir + file) as EcsBuildingDef
		var t := _setup(Vector2i(48, 16))
		var plans: Array = []
		for turns in 4:
			var plan := EcsBuildingStamp.commands(def, CATALOG, ENTITIES, Vector2i(1 + turns * 12, 1), turns)
			plans.append(plan)
			_send(t, plan)
		_send(t, [])
		_send(t, [])
		var want := _rooms_of(t, _building_at(t, Vector2i(1, 1)))
		for turns in 4:
			if not _all_ok(plans[turns]) or _rooms_of(t, _building_at(t, Vector2i(1 + turns * 12, 1))) != want:
				clean = false
				bad.append("%s turned %d" % [def.key, turns])
		t.root.queue_free()
	_check("%d shipped building defs stamp clean in all four turns, same rooms%s" % [files.size(),
		"" if clean else " (not %s)" % [bad]], clean)

func _check(what: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
	print("[town] %s  %s" % ["ok  " if passed else "FAIL", what])
