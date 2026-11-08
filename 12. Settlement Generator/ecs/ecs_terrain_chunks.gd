class_name EcsTerrainChunks
extends RefCounted

## The L1 chunks of a region and what each has: its terrain planned, drawn, its objects planned,
## drawn. Kept in memory, so a chunk is never planned twice. Says what to do next: every stage of
## the chunks in view, nearest the view's centre first, before any of the ring around them, and
## within that terrain before drawing it, before objects, before drawing them.

enum Stage { TERRAIN, DRAW_TERRAIN, OBJECTS, DRAW_OBJECTS }

## L1 cells per chunk side.
var size: int
## Chunks across the region.
var count: Vector2i
## Chunk -> {terrain, nodes, drawn, objects_drawn, busy}; a missing key means not yet.
var chunks: Dictionary = {}

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
