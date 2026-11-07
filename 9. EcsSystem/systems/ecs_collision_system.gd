class_name EcsCollisionSystem
extends EcsSystem

## Soft collision: pushes overlapping solid bodies apart after movement.
## Pairs come from each body's Area2D enter/exit signals (one physics tick old); positions
## come from components. Non-solid bodies are skipped, immovable ones push but never move.

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

# Synced on a rebuild or an edit, the only times radius and is_solid change.
var _radii := PackedFloat32Array()
var _solid: Array[bool] = []
var _edits_seen: int = -1

# Overlapping pairs, Vector2i(owner id, other id), kept by the areas' signals.
var _contacts: Dictionary = {}
var _connected: Dictionary = {}  # entity id -> [area, entered callable, exited callable]

## Times the shapes were synced onto the areas. For tests.
var synced: int = 0

func _init(manager: EcsEntityManager) -> void:
	_manager = manager

func label() -> StringName:
	return &"collision"

func run(world: EcsWorld, _delta: float) -> void:
	if _manager == null:
		return
	var edits := world.get_singleton(EcsEditSingleton) as EcsEditSingleton
	var edited := edits.applied if edits != null else 0
	if _refresh(world) or edited != _edits_seen:
		_edits_seen = edited
		_sync()
	_resolve(EcsRandomSingleton.of(world))

## Number of overlapping pairs on record, each counted from both sides. For tests.
func contacts() -> int:
	return _contacts.size()

## Rebuilds the working set if a body was born or died, or gained or lost movement; true if it did.
func _refresh(world: EcsWorld) -> bool:
	var bodies := world.view([EcsPositionComponent, EcsBodyComponent])
	var movers := world.view([EcsBodyComponent, EcsMovementComponent])
	if bodies == _bodies_view and movers == _movers_view:
		return false
	_drop_set()
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
	_reconnect()
	return true

## Connects the areas of new bodies, and forgets gone ones and their pairs. A newly
## connected area that already overlaps something (a body switched back on) is seeded.
func _reconnect() -> void:
	for id: int in _connected.keys():
		var slot: int = _slots.get(id, -1)
		if slot < 0 or _areas[slot] != _connected[id][0]:
			_disconnect(id)
	for pair: Vector2i in _contacts.keys():
		if not _slots.has(pair.x) or not _slots.has(pair.y):
			_contacts.erase(pair)
	for i in _ids.size():
		var id := _ids[i]
		if _connected.has(id):
			continue
		var area := _areas[i]
		var entered := _on_entered.bind(id)
		var exited := _on_exited.bind(id)
		area.area_entered.connect(entered)
		area.area_exited.connect(exited)
		_connected[id] = [area, entered, exited]
		for other in area.get_overlapping_areas():
			if other is EcsEntityArea and other.entity_id != id:
				_contacts[Vector2i(id, other.entity_id)] = true
				_contacts[Vector2i(other.entity_id, id)] = true

func _disconnect(id: int) -> void:
	var entry: Array = _connected[id]
	var area = entry[0]  # Untyped: a dead entity's area is already freed.
	if is_instance_valid(area):
		if area.area_entered.is_connected(entry[1]):
			area.area_entered.disconnect(entry[1])
		if area.area_exited.is_connected(entry[2]):
			area.area_exited.disconnect(entry[2])
	_connected.erase(id)

func _on_entered(other: Area2D, id: int) -> void:
	if is_instance_valid(other) and other is EcsEntityArea and other.entity_id != id:
		_contacts[Vector2i(id, (other as EcsEntityArea).entity_id)] = true

func _on_exited(other: Area2D, id: int) -> void:
	if is_instance_valid(other) and other is EcsEntityArea:
		_contacts.erase(Vector2i(id, (other as EcsEntityArea).entity_id))

## Writes each body's shape, radius and solidity onto its area.
func _sync() -> void:
	synced += 1
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
## touches. Each pair is on record from both sides, so the push is symmetric.
func _resolve(rng: RandomNumberGenerator) -> void:
	for pair: Vector2i in _contacts:
		var i: int = _slots.get(pair.x, -1)
		var slot: int = _slots.get(pair.y, -1)
		if i < 0 or slot < 0 or not _movable[i] or not _solid[i] or not _solid[slot]:
			continue
		var mine := _places[i]
		if _shapes[i].shape != null or _shapes[slot].shape != null:
			mine.position += _shape_push(i, slot, rng) * 0.5
			continue
		var apart := mine.position - _places[slot].position
		var touching := _radii[i] + _radii[slot]
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

## Clears the working set and the pairs, and disconnects every area; the next run rebuilds.
func clear() -> void:
	for id: int in _connected.keys():
		_disconnect(id)
	_contacts.clear()
	_edits_seen = -1
	_drop_set()

func _drop_set() -> void:
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
