class_name EcsTerrainChunks
extends RefCounted

## The L1 chunks of a region and what each has: its terrain planned, drawn, its objects planned,
## drawn. Kept in memory, so a chunk is never planned twice. Says what to do next: every stage of
## the chunks in view, nearest the view's centre first, before any of the ring around them, and
## within that terrain before drawing it, before objects, before drawing them. A town over the
## chunks (`site`) gives the chunks it covers its commands and keeps their nodes off its ground.

enum Stage { TERRAIN, DRAW_TERRAIN, OBJECTS, DRAW_OBJECTS }

## L1 cells per chunk side.
var size: int
## Chunks across the region.
var count: Vector2i
## Chunk -> {terrain, nodes, drawn, objects_drawn, busy, rev}; a missing key means not yet.
var chunks: Dictionary = {}
## The town over the chunks, or null.
var site: EcsSettlementSite

func _init(region_size: Vector2i, scale: int, chunk_size: int) -> void:
	size = chunk_size
	count = Vector2i(ceili(region_size.x * scale / float(chunk_size)), ceili(region_size.y * scale / float(chunk_size)))

## The chunk holding L1 cell `cell`.
func chunk_at(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(cell.x / float(size)), floori(cell.y / float(size)))

## The chunks over `view` (L1 cells), nearest its centre first, then `ring` more chunks round them.
func around(view: Rect2i, ring: int) -> Array[Vector2i]:
	var first := chunk_at(view.position).clamp(Vector2i.ZERO, count - Vector2i.ONE)
	var last := chunk_at(view.end - Vector2i.ONE).clamp(Vector2i.ZERO, count - Vector2i.ONE)
	var centre := Vector2(view.get_center()) / size - Vector2(0.5, 0.5)
	var inside: Array[Vector2i] = []
	var outside: Array[Vector2i] = []
	for y in range(maxi(first.y - ring, 0), mini(last.y + ring, count.y - 1) + 1):
		for x in range(maxi(first.x - ring, 0), mini(last.x + ring, count.x - 1) + 1):
			var at := Vector2i(x, y)
			if x >= first.x and x <= last.x and y >= first.y and y <= last.y:
				inside.append(at)
			else:
				outside.append(at)
	var nearest := func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(a).distance_squared_to(centre) < Vector2(b).distance_squared_to(centre)
	inside.sort_custom(nearest)
	outside.sort_custom(nearest)
	return inside + outside

## The next {chunk, stage} for `view` with `ring`, or {} when there is nothing to do.
func next_job(view: Rect2i, ring: int) -> Dictionary:
	var order := around(view, ring)
	var visible := around(view, 0).size()
	for part in 2:
		var from := 0 if part == 0 else visible
		var to := visible if part == 0 else order.size()
		for stage in Stage.size():
			for k in range(from, to):
				var at := order[k]
				var chunk: Dictionary = chunks.get(at, {})
				if not chunk.get("busy", false) and _needs(chunk, stage):
					return {"chunk": at, "stage": stage}
	return {}

## Drawn chunks more than `keep` chunks outside `view`, to free their nodes; their plans stay.
func far(view: Rect2i, keep: int) -> Array[Vector2i]:
	var near := Rect2i(chunk_at(view.position), chunk_at(view.end - Vector2i.ONE) - chunk_at(view.position) + Vector2i.ONE).grow(keep)
	var out: Array[Vector2i] = []
	for at: Vector2i in chunks:
		if chunks[at].get("drawn", false) and not chunks[at].get("busy", false) and not near.has_point(at):
			out.append(at)
	return out

## The town's commands for chunk `at`, moved onto the chunk's own grid (its border one cell in).
func overlay(at: Vector2i, objects: bool) -> Array[EcsBuildCommand]:
	if site == null:
		return []
	return clip(site, Rect2i(at * size, Vector2i(size, size)), 1, objects)

## `site`'s commands for the cells of `own` and `border` cells round it, moved so `own` starts at
## (border, border): floors, walls and doors on those cells, so one split across grids joins; a
## building clipped to them, its sides that go on past them marked cut; objects, when asked, only
## on `own`'s cells, so none is placed twice (a piece is at most 2 cells, so it stays in the border).
static func clip(site: EcsSettlementSite, own: Rect2i, border: int, objects: bool) -> Array[EcsBuildCommand]:
	var out: Array[EcsBuildCommand] = []
	var outer := own.grow(border)
	var shift := Vector2i(border, border) - own.position
	for command in site.commands:
		var local := command.cell + shift
		if command.kind == EcsBuildCommand.Kind.CREATE_BUILDING:
			var part := command.rect.intersection(outer)
			if part.has_area():
				var cut := 0
				cut |= EcsBuildingComponent.CUT_LEFT if command.rect.position.x < part.position.x else 0
				cut |= EcsBuildingComponent.CUT_UP if command.rect.position.y < part.position.y else 0
				cut |= EcsBuildingComponent.CUT_RIGHT if command.rect.end.x > part.end.x else 0
				cut |= EcsBuildingComponent.CUT_DOWN if command.rect.end.y > part.end.y else 0
				out.append(EcsBuildCommand.create_building(Rect2i(part.position + shift, part.size), false, cut))
		elif command.kind == EcsBuildCommand.Kind.PLACE_OBJECT:
			if objects and own.has_point(command.cell):
				# A piece reaching past the clip's ground goes only to a clip holding all of it.
				var place := EcsBuildRules.template(EcsTownBuilder.ENTITIES, command.blueprint, &"grid_position") as EcsGridPositionComponent
				var covers := Rect2i(command.cell, EcsTownGrid.turned(place.size if place != null else Vector2i.ONE, command.value))
				if outer.encloses(covers):
					out.append(EcsBuildCommand.place(command.kind, local, command.blueprint, command.value))
		elif outer.has_point(command.cell):
			# A door on the clip's outer ring has lost a wall beside it past the cut; it stays wall.
			if command.kind == EcsBuildCommand.Kind.PLACE_DOOR and not outer.grow(-1).has_point(command.cell):
				continue
			out.append(EcsBuildCommand.make(command.kind, local, command.value))
	return out

## Chunk `at`'s cells the town clears, as 1s over its `size` × `size` cells, for refine_nodes;
## empty when it clears none.
func blocked(at: Vector2i) -> PackedByteArray:
	var out := PackedByteArray()
	if site == null:
		return out
	var own := Rect2i(at * size, Vector2i(size, size))
	for rect in site.cleared:
		var part := rect.intersection(own)
		if part.has_area():
			if out.is_empty():
				out.resize(size * size)
			for y in range(part.position.y, part.end.y):
				for x in range(part.position.x, part.end.x):
					out[(y - own.position.y) * size + x - own.position.x] = 1
	for cell: Vector2i in site.cleared_cells:
		if own.has_point(cell):
			if out.is_empty():
				out.resize(size * size)
			out[(cell.y - own.position.y) * size + cell.x - own.position.x] = 1
	return out

## The chunks `rect` (L1 cells) touches, its border cells included.
func touching(rect: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not rect.has_area():
		return out
	var first := chunk_at(rect.position - Vector2i.ONE).clamp(Vector2i.ZERO, count - Vector2i.ONE)
	var last := chunk_at(rect.end).clamp(Vector2i.ZERO, count - Vector2i.ONE)
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			out.append(Vector2i(x, y))
	return out

## How many chunks have reached each stage: [terrain planned, drawn, objects planned, objects drawn].
func tally() -> Array[int]:
	var out: Array[int] = [0, 0, 0, 0]
	for at: Vector2i in chunks:
		var chunk: Dictionary = chunks[at]
		out[0] += 1 if chunk.has("terrain") else 0
		out[1] += 1 if chunk.get("drawn", false) else 0
		out[2] += 1 if chunk.has("nodes") else 0
		out[3] += 1 if chunk.get("objects_drawn", false) else 0
	return out

func _needs(chunk: Dictionary, stage: int) -> bool:
	match stage:
		Stage.TERRAIN:
			return not chunk.has("terrain")
		Stage.DRAW_TERRAIN:
			return chunk.has("terrain") and not chunk.get("drawn", false)
		Stage.OBJECTS:
			return chunk.get("drawn", false) and not chunk.has("nodes")
		Stage.DRAW_OBJECTS:
			return chunk.get("drawn", false) and chunk.has("nodes") and not chunk.get("objects_drawn", false)
	return false
