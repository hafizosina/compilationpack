class_name EcsCollisionSystem
extends EcsSystem

## Keeps bodies out of each other, using Godot's physics broadphase to find the
## overlapping pairs and plain component maths to resolve them.
##
## Runs straight after movement: movement proposes a position, this corrects it,
## and neither knows the other exists. Applying it as a constraint after the
## fact is what makes it compose — anything else that ever writes a position
## (knockback, a spawner, a debug teleport) gets cleaned up for free.
##
## ## Why a node pool, in a module that says entities are not nodes
##
## Finding which circles overlap is a spatial index problem, and Godot already
## ships one written in C++. Doing it in GDScript costs O(n²): measured on this
## machine, 800 entities took 202ms a frame that way and 9.5ms this way.
##
## The rule this bends is "nothing reads back off a node", so be precise about
## what is happening. `EcsPositionComponent` is still the only truth. The Area2D
## pool is a **derived index**, rebuilt from those components every tick, and
## the only thing read back off it is *which pairs are near each other* — never
## where anything is. Delete the pool and the simulation is still complete.
##
## That is a different thing from module 8, where the node WAS the entity. If a
## future system starts reading state off these areas, that line has been
## crossed and this comment is the place it was agreed.
##
## ## The one-tick lag
##
## `get_overlapping_areas()` reports what the physics server saw at the end of
## the last step, so a correction is always one tick behind the positions that
## caused it. That is fine here and is the reason this is cheap: the list is
## maintained by the server rather than queried. At 60Hz and walking speeds it
## is about two pixels of extra overlap, invisible.
##
## It does mean the relaxation passes the GDScript version used are gone — the
## overlap list cannot be refreshed mid-tick. One pass per tick, converging over
## a few ticks instead. `PhysicsDirectSpaceState2D.intersect_shape()` is the
## synchronous alternative if that ever matters; it costs a query per body.
##
## Carrying an EcsShapeComponent is what makes an entity solid. Anything without
## one never gets a body, so it passes through everything with no `solid` flag,
## no layer mask and no branch.

## Parent for the pooled bodies. They are invisible; only the physics server
## ever looks at them.
var _root: Node2D
var _bodies: Dictionary = {}   # entity id -> Area2D
var _circles: Dictionary = {}  # entity id -> CircleShape2D

# Per-tick gather. `_sync` collects the component references once into parallel
# arrays and `_resolve` then works off those, touching the world not at all.
#
# This is not premature tuning, it is where the time actually goes: the physics
# broadphase costs about 0.2ms at 100 entities, while calling `get_component`
# a few hundred times a tick to ask the same questions costs ten times that.
# Gathering once is the difference between this system being cheap and not.
var _ids: Array[int] = []
var _places: Array[EcsPositionComponent] = []
var _radii := PackedFloat32Array()
var _slots: Dictionary = {}  # entity id -> index into the arrays above

func _init(root: Node2D) -> void:
	_root = root

func label() -> StringName:
	return &"collision"

func run(world: EcsWorld, _delta: float) -> void:
	if _root == null:
		return
	_sync(world)
	_resolve()

## Brings the body pool in line with the world: one Area2D per entity holding
## both a position and a shape, created when an id starts matching and freed
## when it stops. Data flows one way, component -> node.
func _sync(world: EcsWorld) -> void:
	_ids.clear()
	_places.clear()
	_radii.clear()
	_slots.clear()

	var live: Dictionary = {}
	for id in world.query([EcsPositionComponent, EcsShapeComponent]):
		live[id] = true
		var body: Area2D = _bodies.get(id)
		var shape := world.get_component(id, EcsShapeComponent) as EcsShapeComponent
		if body == null:
			body = Area2D.new()
			body.name = "body_%d" % id
			# Monitoring finds the overlaps; monitorable lets others find this
			# one. Nothing here pushes anything, so no physics response exists.
			body.monitoring = true
			body.monitorable = true
			var circle := CircleShape2D.new()
			circle.radius = shape.radius
			var collider := CollisionShape2D.new()
			collider.shape = circle
			body.add_child(collider)
			body.set_meta(&"entity_id", id)
			_root.add_child(body)
			_bodies[id] = body
			_circles[id] = circle
		else:
			var circle: CircleShape2D = _circles[id]
			if not is_equal_approx(circle.radius, shape.radius):
				circle.radius = shape.radius
		var place := world.get_component(id, EcsPositionComponent) as EcsPositionComponent
		body.position = place.position

		_slots[id] = _ids.size()
		_ids.append(id)
		_places.append(place)
		_radii.append(shape.radius)

	for id: int in _bodies.keys():
		if not live.has(id):
			_free_body(id)

## Pushes each body clear of everything the physics server says it overlaps.
##
## Every pair is reported twice — A sees B and B sees A — and rather than
## deduplicating, each body moves only *itself*, by half the overlap. The double
## report is what makes the correction symmetric, for free.
func _resolve() -> void:
	for i in _ids.size():
		var mine := _places[i]
		var my_radius := _radii[i]
		for other in (_bodies[_ids[i]] as Area2D).get_overlapping_areas():
			var slot: int = _slots.get(other.get_meta(&"entity_id", EcsWorld.NO_ENTITY), -1)
			if slot < 0:
				continue

			var apart := mine.position - _places[slot].position
			var touching := my_radius + _radii[slot]
			var gap := apart.length()
			if gap >= touching:
				continue

			# Exactly stacked: no direction to separate along, so pick one.
			var push := apart / gap if gap > 0.01 else Vector2.RIGHT.rotated(randf() * TAU)
			mine.position += push * (touching - gap) * 0.5

## Drops every body. Called when the world is rebuilt.
func clear() -> void:
	for id: int in _bodies.keys():
		_free_body(id)

func _free_body(id: int) -> void:
	# Detached before freeing: queue_free() leaves the node parented until the
	# end of the frame, so a respawn in the same frame would double up.
	var body: Area2D = _bodies[id]
	_root.remove_child(body)
	body.queue_free()
	_bodies.erase(id)
	_circles.erase(id)
