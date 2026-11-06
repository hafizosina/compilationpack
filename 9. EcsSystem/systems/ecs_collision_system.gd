class_name EcsCollisionSystem
extends EcsSystem

## Soft collision: pushes overlapping solid bodies apart after movement.
## Pairs come from each body's Area2D (one physics tick old); positions come
## from components. Non-solid bodies are skipped, immovable ones push but never move.

var _manager: EcsEntityManager

# The working set, rebuilt only when one of these views changes.
var _bodies_view: EcsView
var _movers_view: EcsView
var _ids: Array[int] = []
var _places: Array[EcsPositionComponent] = []
var _shapes: Array[EcsBodyComponent] = []
var _circles: Array[CircleShape2D] = []
var _colliders: Array[CollisionShape2D] = []
var _areas: Array[Area2D] = []
var _movable: Array[bool] = []
var _slots: Dictionary = {}  # entity id -> index into the arrays above

# Refreshed every tick, since radius and is_solid can change at any time.
var _radii := PackedFloat32Array()
var _solid: Array[bool] = []

func _init(manager: EcsEntityManager) -> void:
	_manager = manager

func label() -> StringName:
	return &"collision"

func run(world: EcsWorld, _delta: float) -> void:
	if _manager == null:
		return
	_refresh(world)
	_sync()
	_resolve(EcsRandomSingleton.of(world))

## Rebuilds the working set if a body was born or died, or gained or lost movement.
func _refresh(world: EcsWorld) -> void:
	var bodies := world.view([EcsPositionComponent, EcsBodyComponent])
	var movers := world.view([EcsBodyComponent, EcsMovementComponent])
	if bodies == _bodies_view and movers == _movers_view:
		return
	clear()
	_bodies_view = bodies
	_movers_view = movers

	var places := bodies.column(EcsPositionComponent)
	var shapes := bodies.column(EcsBodyComponent)
	for k in bodies.ids.size():
		var id := bodies.ids[k]
		var body := _manager.node_for(id, EcsConst.NODE_BODY) as Area2D
		if body == null:
			continue
		_slots[id] = _ids.size()
		_ids.append(id)
		_places.append(places[k])
		_shapes.append(shapes[k])
		var collider := body.get_node(^"Collider") as CollisionShape2D
		_colliders.append(collider)
		_circles.append(collider.shape as CircleShape2D)
		_areas.append(body)
		_movable.append(false)
	for id in movers.ids:
		var slot: int = _slots.get(id, -1)
		if slot >= 0:
			_movable[slot] = true
	_radii.resize(_ids.size())
	_solid.resize(_ids.size())

## Writes each body's shape, radius and solidity onto its area.
func _sync() -> void:
	for i in _ids.size():
		var shape := _shapes[i]
		var circle := _circles[i]
		var wanted: Shape2D = shape.shape if shape.shape != null else circle
		if _colliders[i].shape != wanted:
			_colliders[i].shape = wanted
		if not is_equal_approx(circle.radius, shape.radius):
			circle.radius = shape.radius
		_radii[i] = shape.radius

		# Non-solid bodies stop monitoring but stay detectable.
		var body := _areas[i]
		var solid := shape.is_solid
		if body.monitoring != solid:
			body.monitoring = solid
		if not body.monitorable:
			body.monitorable = true
		_solid[i] = solid

## Moves each movable solid body half the overlap away from each solid body it
## touches. Each pair is reported from both sides, so the push is symmetric.
func _resolve(rng: RandomNumberGenerator) -> void:
	for i in _ids.size():
		if not _movable[i] or not _solid[i]:
			continue
		var mine := _places[i]
		var my_radius := _radii[i]
		for other: EcsEntityArea in _areas[i].get_overlapping_areas():
			var slot: int = _slots.get(other.entity_id, -1)
			if slot < 0 or not _solid[slot]:
				continue

			if _shapes[i].shape != null or _shapes[slot].shape != null:
				mine.position += _shape_push(i, slot, rng) * 0.5
				continue
			var apart := mine.position - _places[slot].position
			var touching := my_radius + _radii[slot]
			var gap := apart.length()
			if gap >= touching:
				continue

			# Exactly stacked: pick a random direction.
			var push := apart / gap if gap > 0.01 else Vector2.RIGHT.rotated(rng.randf() * TAU)
			mine.position += push * (touching - gap) * 0.5

## How far body `i` must move to stop overlapping body `slot`, either of any shape:
## the deepest of the contact pairs the physics shapes report.
func _shape_push(i: int, slot: int, rng: RandomNumberGenerator) -> Vector2:
	var contacts := _colliders[i].shape.collide_and_get_contacts(
		Transform2D(0.0, _places[i].position), _colliders[slot].shape,
		Transform2D(0.0, _places[slot].position))
	var deepest := Vector2.ZERO
	for k in range(0, contacts.size(), 2):
		var out := contacts[k + 1] - contacts[k]
		if out.length_squared() > deepest.length_squared():
			deepest = out
	if deepest == Vector2.ZERO and not contacts.is_empty():
		# Exactly stacked: pick a random direction.
		deepest = Vector2.RIGHT.rotated(rng.randf() * TAU) * maxf(_radii[i], 1.0)
	return deepest

## Clears the working set; the next run rebuilds it.
func clear() -> void:
	_bodies_view = null
	_movers_view = null
	_ids.clear()
	_places.clear()
	_shapes.clear()
	_circles.clear()
	_colliders.clear()
	_areas.clear()
	_movable.clear()
	_slots.clear()
	_radii.clear()
	_solid.clear()
