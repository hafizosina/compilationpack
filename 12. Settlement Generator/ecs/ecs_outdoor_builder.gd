class_name EcsOutdoorBuilder
extends RefCounted

## Pure and seeded: a plot with no walls laid out by its work's own small rule, on its footprint:
##   market: stone floor, stalls round the back and sides, crates, a notice board by the way in;
##   mine: the entrance at the back, an ore cart, stone piles;
##   quarry: stone piles round the edge, a sawhorse and crates;
##   lumber camp: dirt, log piles along the back, a chopping block, stumps;
##   clay pit: dirt, clay pits in the middle, drying racks round the edge;
##   harbour: crates and mooring posts along the back (its dock is the plot's);
##   shrine: stone floor, the shrine in the middle.
## The way in, the door's cell and the one inside it, is never used. The commands go into the
## site's.

## Lays `plot`; false when its role has no rule.
static func lay(site: EcsSettlementSite, plot: Dictionary, def: EcsSettlementDef, catalog: EcsTownCatalog,
		rng_seed: int) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var lot := Lot.new(site, plot)
	match plot["role"]:
		&"market":
			lot.lay_floor(catalog.floor_id(&"stone"))
			lot.ring(&"market_stall", 3)
			lot.scatter(&"crate", rng.randi_range(1, 3), rng)
			lot.beside_door(&"notice_board")
		&"mine":
			lot.at_back(&"mine_entrance", Vector2i(2, 2))
			lot.scatter(&"ore_cart", 1, rng)
			lot.scatter(&"stone_pile", rng.randi_range(2, 3), rng)
		&"quarry":
			lot.ring(&"stone_pile", 2)
			lot.middle(&"sawhorse")
			lot.scatter(&"crate", 2, rng)
		&"lumber_camp":
			lot.lay_ground(catalog.terrain_id(def.field_terrain))
			lot.ring(&"lumber_pile", 3)
			lot.middle(&"chopping_block")
			lot.scatter(&"stump", rng.randi_range(2, 4), rng)
		&"clay_pit":
			lot.lay_ground(catalog.terrain_id(def.field_terrain))
			lot.middle(&"clay_pit")
			lot.scatter(&"clay_pit", 1, rng)
			lot.ring(&"drying_rack", 2)
		&"harbour":
			lot.ring(&"crate", 3)
			lot.scatter(&"mooring_post", 2, rng)
		&"shrine":
			lot.lay_floor(catalog.floor_id(&"stone"))
			lot.middle(&"shrine")
		_:
			return false
	return true


## A footprint being laid: which cells are taken, and the helpers each rule is built from.
class Lot:
	var site: EcsSettlementSite
	var rect: Rect2i
	var front: Vector2i
	var door: Vector2i
	var taken: Dictionary = {}

	func _init(on: EcsSettlementSite, plot: Dictionary) -> void:
		site = on
		rect = plot["footprint"]
		front = plot["front"]
		door = plot["door"]
		taken[door] = true
		taken[door - front] = true

	## A floor on every cell.
	func lay_floor(id: int) -> void:
		for cell in EcsBuildRules.cells(rect):
			site.commands.append(EcsBuildCommand.make(EcsBuildCommand.Kind.SET_FLOOR, cell, id))

	## Terrain on every cell.
	func lay_ground(id: int) -> void:
		for cell in EcsBuildRules.cells(rect):
			site.commands.append(EcsBuildCommand.make(EcsBuildCommand.Kind.SET_TERRAIN, cell, id))

	## `blueprint` along the back and both sides every `every` cells, its length along the edge.
	func ring(blueprint: StringName, every: int) -> void:
		var size := _size(blueprint)
		for side in [-front, Vector2i(front.y, front.x), Vector2i(-front.y, -front.x)]:
			var along := Vector2i(absi(side.y), absi(side.x))
			var turns := 0 if along.x != 0 else 1
			var covers := EcsTownGrid.turned(size, turns)
			var start := Vector2i(rect.end.x - covers.x if side.x > 0 else rect.position.x,
				rect.end.y - covers.y if side.y > 0 else rect.position.y)
			var length := rect.size.x if along.x != 0 else rect.size.y
			for k in range(1, length - 1, maxi(every, covers.x if along.x != 0 else covers.y)):
				put(blueprint, start + along * k, turns)

	## `blueprint` in the middle, or the nearest spot back from the way in, then to either side.
	func middle(blueprint: StringName) -> void:
		var size := _size(blueprint)
		var mid := rect.position + rect.size / 2 - size / 2
		var along := Vector2i(absi(front.y), absi(front.x))
		for cell in [mid, mid - front, mid - front * 2, mid + along, mid - along]:
			if put(blueprint, cell, 0):
				return

	## `blueprint` in the middle of the back, `size` cells.
	func at_back(blueprint: StringName, size: Vector2i) -> void:
		var back := -front
		var mid := rect.position + rect.size / 2 - size / 2
		var cell := Vector2i(rect.end.x - size.x - 1 if back.x > 0 else (rect.position.x + 1 if back.x < 0 else mid.x),
			rect.end.y - size.y - 1 if back.y > 0 else (rect.position.y + 1 if back.y < 0 else mid.y))
		put(blueprint, cell, 0)

	## `count` of `blueprint` at random free cells inside the edge.
	func scatter(blueprint: StringName, count: int, rng: RandomNumberGenerator) -> void:
		var inside := rect.grow(-1)
		if not inside.has_area():
			inside = rect
		var placed := 0
		for attempt in count * 12:
			if placed >= count:
				return
			var cell := Vector2i(rng.randi_range(inside.position.x, inside.end.x - 1), rng.randi_range(inside.position.y, inside.end.y - 1))
			if put(blueprint, cell, 0):
				placed += 1

	## `blueprint` one cell along the front from the way in.
	func beside_door(blueprint: StringName) -> void:
		var along := Vector2i(absi(front.y), absi(front.x))
		if not put(blueprint, door + along * 2, 0):
			put(blueprint, door - along * 2, 0)

	## Places `blueprint` turned `turns` at `cell` when every cell it covers is in the footprint and
	## free; whether it did.
	func put(blueprint: StringName, cell: Vector2i, turns: int) -> bool:
		var covers := Rect2i(cell, EcsTownGrid.turned(_size(blueprint), turns))
		if not rect.encloses(covers):
			return false
		for c in EcsBuildRules.cells(covers):
			if taken.has(c):
				return false
		for c in EcsBuildRules.cells(covers):
			taken[c] = true
		site.commands.append(EcsBuildCommand.place(EcsBuildCommand.Kind.PLACE_OBJECT, cell, blueprint, turns))
		return true

	func _size(blueprint: StringName) -> Vector2i:
		var place := EcsBuildRules.template(EcsTownBuilder.ENTITIES, blueprint, &"grid_position") as EcsGridPositionComponent
		return place.size if place != null else Vector2i.ONE
