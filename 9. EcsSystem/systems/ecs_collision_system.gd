class_name EcsCollisionSystem
extends EcsSystem

## Soft collision: pushes overlapping solid bodies apart after movement.
## Pairs come from each body's Area2D (one physics tick old); positions come
## from components. Non-solid bodies are skipped, immovable ones push but never move.

var _manager: EcsEntityManager
var _circles: Dictionary = {}  # entity id -> CircleShape2D, resolved once

# This tick's bodies, gathered once by `_sync` and read by `_resolve`.
var _ids: Array[int] = []
var _places: Array[EcsPositionComponent] = []
var _radii := PackedFloat32Array()
var _movable: Array[bool] = []
var _solid: Array[bool] = []
var _areas: Array[Area2D] = []
var _slots: Dictionary = {}  # entity id -> index into the arrays above

func _init(manager: EcsEntityManager) -> void:
	_manager = manager

func label() -> StringName:
	return &"collision"

func run(world: EcsWorld, _delta: float) -> void:
	if _manager == null:
		return
	_sync(world)
	_resolve()

## Writes each body's radius and solidity to its area and gathers the working set.
func _sync(world: EcsWorld) -> void:
	_ids.clear()
	_places.clear()
	_radii.clear()
	_movable.clear()
	_solid.clear()
	_areas.clear()
	_slots.clear()

	for id in world.query([EcsPositionComponent, EcsBodyComponent]):
		var body := _manager.node_for(id, EcsConst.NODE_BODY) as Area2D
		if body == null:
			_circles.erase(id)
			continue

		var shape := world.get_component(id, EcsBodyComponent) as EcsBodyComponent
		var circle: CircleShape2D = _circles.get(id)
		if circle == null:
			circle = (body.get_node(^"Collider") as CollisionShape2D).shape as CircleShape2D
			_circles[id] = circle
		if not is_equal_approx(circle.radius, shape.radius):
			circle.radius = shape.radius

		var place := world.get_component(id, EcsPositionComponent) as EcsPositionComponent
		# Non-solid bodies stop monitoring but stay detectable.
		var solid := shape.is_solid
		if body.monitoring != solid:
			body.monitoring = solid
		if not body.monitorable:
			body.monitorable = true

		_slots[id] = _ids.size()
		_ids.append(id)
		_places.append(place)
		_radii.append(shape.radius)
		_movable.append(world.has(id, EcsMovementComponent))
		_solid.append(solid)
		_areas.append(body)

## Moves each movable solid body half the overlap away from each solid body it
## touches. Each pair is reported from both sides, so the push is symmetric.
func _resolve() -> void:
	for i in _ids.size():
		if not _movable[i] or not _solid[i]:
			continue
		var mine := _places[i]
		var my_radius := _radii[i]
		for other: EcsEntityArea in _areas[i].get_overlapping_areas():
			var slot: int = _slots.get(other.entity_id, -1)
			if slot < 0 or not _solid[slot]:
				continue

			var apart := mine.position - _places[slot].position
			var touching := my_radius + _radii[slot]
			var gap := apart.length()
			if gap >= touching:
				continue

			# Exactly stacked: pick a random direction.
			var push := apart / gap if gap > 0.01 else Vector2.RIGHT.rotated(randf() * TAU)
			mine.position += push * (touching - gap) * 0.5

## Clears the working set and cached shapes.
func clear() -> void:
	_circles.clear()
	_ids.clear()
	_places.clear()
	_radii.clear()
	_movable.clear()
	_solid.clear()
	_areas.clear()
	_slots.clear()
