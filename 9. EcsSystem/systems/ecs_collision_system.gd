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
## what is happening. `EcsPositionComponent` is still the only truth. The areas
## are a **derived index**: every tick this system writes each body's position
## and radius out of the components, and the only thing it reads back is *which
## pairs are near each other* — never where anything is. Delete the areas and
## the simulation is still complete.
##
## What changed with EcsEntityManager is who makes them, not what they mean.
## This system used to create a body the tick an id started matching its query
## and free it the tick it stopped. Now the manager builds one at spawn for any
## entity whose EcsShapeComponent declares it, and frees it when the entity
## dies — so the node's lifetime follows the entity, while whether it collides
## at all still follows the components. A berry in an inventory keeps its area
## and has it switched off, because an entity with no position is not anywhere
## to collide.
##
## It no longer writes the body's position either. The area hangs under that
## entity's `entity_<id>` container at local zero, so it goes where the
## container goes, and EcsNodeSyncSystem moves the container. This system writes
## only what is its own: the radius, and whether the body is live at all.
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
## one never gets a body, so it passes through everything with no `solid` flag
## and no branch.
##
## **Solid and movable are different questions.** A berry is solid — it has a
## body, so sensors can see it and action areas can touch it — but it has no
## EcsMovementComponent, and a thing that cannot move cannot be pushed. Without
## that rule a forager would shove the berry it was walking toward and chase it
## across the arena. Again it is component presence doing the work: no
## `is_static` flag, and the same rule will hold for a tree or a rock.

## Where the bodies come from. They are invisible; only the physics server
## ever looks at them.
var _manager: EcsEntityManager
var _circles: Dictionary = {}  # entity id -> CircleShape2D, resolved once

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
var _movable: Array[bool] = []
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

## Writes the radius out onto each body and gathers this tick's working set.
## Data flows one way, component -> node; nothing here creates, frees or moves.
func _sync(world: EcsWorld) -> void:
	_ids.clear()
	_places.clear()
	_radii.clear()
	_movable.clear()
	_areas.clear()
	_slots.clear()

	for id in world.query([EcsPositionComponent, EcsShapeComponent]):
		var body := _manager.node_for(id, EcsConst.NODE_BODY) as Area2D
		if body == null:
			# The entity is gone and took its body with it.
			_circles.erase(id)
			continue

		var shape := world.get_component(id, EcsShapeComponent) as EcsShapeComponent
		var circle: CircleShape2D = _circles.get(id)
		if circle == null:
			# Resolved once per entity rather than every tick: the manager
			# builds the body bare, and this is the first look inside it.
			circle = (body.get_node(^"Collider") as CollisionShape2D).shape as CircleShape2D
			_circles[id] = circle
		if not is_equal_approx(circle.radius, shape.radius):
			circle.radius = shape.radius

		var place := world.get_component(id, EcsPositionComponent) as EcsPositionComponent
		if not body.monitoring:
			body.monitoring = true
			body.monitorable = true

		_slots[id] = _ids.size()
		_ids.append(id)
		_places.append(place)
		_radii.append(shape.radius)
		_movable.append(world.has(id, EcsMovementComponent))
		_areas.append(body)

	# A body whose entity has stopped being anywhere is switched off rather
	# than destroyed. Left on, a held berry would go on shoving whatever walked
	# over the spot it was picked up from.
	for id in world.query([EcsShapeComponent], [EcsPositionComponent]):
		var body := _manager.node_for(id, EcsConst.NODE_BODY) as Area2D
		if body != null and body.monitoring:
			body.monitoring = false
			body.monitorable = false

## Pushes each body clear of everything the physics server says it overlaps.
##
## Every pair is reported twice — A sees B and B sees A — and rather than
## deduplicating, each body moves only *itself*, by half the overlap. The double
## report is what makes the correction symmetric, for free.
func _resolve() -> void:
	for i in _ids.size():
		if not _movable[i]:
			# It is still in the arrays, because everything else has to be
			# pushed out of *it*. It just never moves itself.
			continue
		var mine := _places[i]
		var my_radius := _radii[i]
		for other: EcsEntityArea in _areas[i].get_overlapping_areas():
			var slot: int = _slots.get(other.entity_id, -1)
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

## Forgets this tick's working set and the resolved shape lookups. The bodies
## themselves belong to EcsEntityManager and are freed there.
func clear() -> void:
	_circles.clear()
	_ids.clear()
	_places.clear()
	_radii.clear()
	_movable.clear()
	_areas.clear()
	_slots.clear()
