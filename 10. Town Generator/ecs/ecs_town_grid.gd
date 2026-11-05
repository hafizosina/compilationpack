class_name EcsTownGrid
extends RefCounted

## Pure helpers over EcsTownGridSingleton: cell maths and creating an empty grid.

## Pixels per cell side.
const CELL: int = 32

## A `width` x `height` grid of `base_terrain`, nothing else on it.
static func make(width: int, height: int, base_terrain: int) -> EcsTownGridSingleton:
	var grid := EcsTownGridSingleton.new()
	grid.width = width
	grid.height = height
	var n := width * height
	for layer: String in ["terrain", "floor", "structure", "wall_type", "roof"]:
		var cells := PackedInt32Array()
		cells.resize(n)
		grid.set(layer, cells)
	for layer: String in ["building_id", "object_id", "attachment_id", "room_id"]:
		var cells := PackedInt32Array()
		cells.resize(n)
		cells.fill(-1)
		grid.set(layer, cells)
	grid.terrain.fill(base_terrain)
	return grid

static func in_bounds(grid: EcsTownGridSingleton, cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid.width and cell.y < grid.height

static func index(grid: EcsTownGridSingleton, cell: Vector2i) -> int:
	return cell.y * grid.width + cell.x

## The cell under a world position.
static func cell_at(world_position: Vector2) -> Vector2i:
	return Vector2i((world_position / CELL).floor())

## A `size` footprint after `turns` quarter turns clockwise.
static func turned(size: Vector2i, turns: int) -> Vector2i:
	return size if posmod(turns, 2) == 0 else Vector2i(size.y, size.x)

## `cell` of a `size` footprint after `turns` quarter turns clockwise.
static func turn(cell: Vector2i, size: Vector2i, turns: int) -> Vector2i:
	for k in posmod(turns, 4):
		cell = Vector2i(size.y - 1 - cell.y, cell.x)
		size = Vector2i(size.y, size.x)
	return cell

## `rect` inside a `size` footprint after `turns` quarter turns clockwise.
static func turn_rect(rect: Rect2i, size: Vector2i, turns: int) -> Rect2i:
	for k in posmod(turns, 4):
		rect = Rect2i(Vector2i(size.y - rect.end.y, rect.position.x), Vector2i(rect.size.y, rect.size.x))
		size = Vector2i(size.y, size.x)
	return rect

## The world position of a cell's centre.
static func centre_of(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * CELL
