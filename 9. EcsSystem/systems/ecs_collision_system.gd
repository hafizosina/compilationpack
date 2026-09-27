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
## entity whose EcsBodyComponent declares it, and frees it when the entity
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
## ## Having a body, being solid, and being movable are three questions
##
## Carrying an EcsBodyComponent gives an entity a body: a radius, and an area on
## the body layer so sensors can see it and action areas can reach it. That
## component's `is_solid` is what makes the body *block* — what puts it in this
## system's resolve at all.
##
## They were one question until a berry made the case for two. A berry needs a
## body for exactly one reason, to be perceived and picked up, and being shoved
## aside by every passing forager was never part of the deal: it held the
## forager a body's width short of the thing it walked over to get. So ground
## items — berries, corpses, a dropped tool — carry a body with `is_solid` off,
## and everything walks over them.
##
## A non-solid body is still gathered below, because the radius written onto its
## area each tick is what sensors detect it at. It is skipped only where it
## would push or be pushed.
##
## **Movable is the third question, and it is EcsMovementComponent.** A bush is
## solid and immovable: walkers are pushed out of it and it never yields. A
## berry is neither. A rabbit is both.

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

## Writes the radius out onto each body and gathers this tick's working set.
## Data flows one way, component -> node; nothing here creates, frees or moves.
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
			# The entity is gone and took its body with it.
			_circles.erase(id)
			continue

		var shape := world.get_component(id, EcsBodyComponent) as EcsBodyComponent
		var circle: CircleShape2D = _circles.get(id)
		if circle == null:
			# Resolved once per entity rather than every tick: the manager
			# builds the body bare, and this is the first look inside it.
			circle = (body.get_node(^"Collider") as CollisionShape2D).shape as CircleShape2D
			_circles[id] = circle
		if not is_equal_approx(circle.radius, shape.radius):
			circle.radius = shape.radius

		var place := world.get_component(id, EcsPositionComponent) as EcsPositionComponent
		# A body that takes no part in collision has nothing to watch for, so it
		# stops monitoring — but it stays monitorable, because being seen is the
		# whole reason it has a body. That one line is the difference between a
		# rabbit and a berry lying on the ground.
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

## Pushes each body clear of everything the physics server says it overlaps.
##
## Every pair is reported twice — A sees B and B sees A — and rather than
## deduplicating, each body moves only *itself*, by half the overlap. The double
## report is what makes the correction symmetric, for free.
func _resolve() -> void:
	for i in _ids.size():
		if not _movable[i] or not _solid[i]:
			# Immovable and still solid — a bush — stays in the arrays because
			# everything else has to be pushed out of *it*; it just never moves
			# itself. Not solid at all — a berry — is in them only so its radius
			# reaches its area, and takes no part in this at either end.
			continue
		var mine := _places[i]
		var my_radius := _radii[i]
		for other: EcsEntityArea in _areas[i].get_overlapping_areas():
			var slot: int = _slots.get(other.entity_id, -1)
			if slot < 0 or not _solid[slot]:
				# A ground item is overlapped, not collided with. The physics
				# server still reports it, because a berry must stay detectable
				# for the sensor; solidity is decided here, not by the layer.
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
	_solid.clear()
	_areas.clear()
	_slots.clear()
