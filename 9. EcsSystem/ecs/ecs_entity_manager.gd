class_name EcsEntityManager
extends RefCounted

## The one owner of structure: the only code in module 9 that creates or
## destroys an entity id, its component data, or its nodes.
##
## It replaces EcsEntityFactory and takes over the node creation that used to
## be smeared across two systems. EcsRenderSystem made a Sprite2D on first
## query match; EcsCollisionSystem made an Area2D the same way. Two lifetimes,
## both implicit, each carrying its own copy of the detach-before-free
## subtlety. Birth and death now happen in one file at one instant in the frame.
##
## What it deliberately does NOT do is update nodes. Creating and destroying is
## this file; writing positions, textures and radii every tick belongs to
## EcsNodeSyncSystem and EcsCollisionSystem, which own those values. Hold that
## line or this becomes the god object the split was meant to avoid.
##
## It is a service rather than an EcsSystem — a peer of EcsWorld, owning
## structure the way the world owns data — so that the systems looking nodes up
## on it are not reaching into another system. EcsLifecycleSystem is the twenty
## lines that put its drain in the pipeline where the run order is readable.
##
## Nodes are grouped per entity, not pooled per kind:
##
##     World/Entities/
##       entity_12/              ← plain Node2D, holds no logic and no data
##         Sprite2D
##         Area2dForBody
##       entity_13/
##         Sprite2D
##
## The container carries the entity's transform, so its children sit at local
## zero and inherit it — one position written per entity however many concerns
## it grows, one lifetime, and a remote scene tree that reads as a list of
## entities instead of two parallel pools to cross-reference by id.
##
## The rule this structure is one step away from, and must not take: in module 8
## the node WAS the entity. Here `entity_12` is a *container*, not an entity. It
## holds no script, no data and no state, nothing reads anything back off it,
## and deleting every one of them leaves the simulation complete. If something
## ever hangs state on a container, that line has been crossed and this comment
## is where it was agreed.

var _root: Node2D
var _containers: Dictionary = {}  # entity id -> Node2D container
var _nodes: Dictionary = {}       # entity id -> { node kind -> Node2D }
var _serial: int = 0
var _crypto := Crypto.new()

func _init(root: Node2D) -> void:
	_root = root

## Wipes every node and spawns one entity per `world_def.entries` row. Called
## once at startup and again on F5.
func spawn_world(world: EcsWorld, catalog: EcsEntityCatalog, world_def: EcsWorldDef) -> void:
	if world == null or catalog == null or world_def == null:
		push_error("EcsEntityManager: world, catalog and world_def must all be set")
		return
	clear()
	for placement in world_def.entries:
		if placement == null:
			continue
		spawn(world, catalog, placement.type, placement.position,
			placement.overrides, placement.entity_name)

## Fulfils every note raised since the last tick, births before deaths.
##
## Each queue is taken and replaced with an empty one before it is walked, so a
## request raised while draining lands on the next tick rather than extending
## this one — a spawner that spawns spawners cannot lock up the frame.
func drain(world: EcsWorld, catalog: EcsEntityCatalog) -> void:
	var inbox := world.get_singleton(EcsLifecycleSingleton) as EcsLifecycleSingleton
	if inbox == null:
		return

	var births := inbox.spawn_requests
	inbox.spawn_requests = []
	for request in births:
		request.born = spawn(world, catalog, request.type_id, request.position,
			request.overrides, request.entity_name)
		request.fulfilled = true

	# Everything claimed for death since the last drain. The query is taken
	# whole before the first kill, so destroying one cannot disturb the walk.
	for id in world.query([EcsDyingFlag]):
		kill(world, id)

## Builds one entity of `type_id` at `pos` and returns its id, or NO_ENTITY.
func spawn(world: EcsWorld, catalog: EcsEntityCatalog, type_id: StringName, pos: Vector2,
		overrides: Dictionary = {}, entity_name: StringName = &"") -> int:
	var blueprint := catalog.get_def(type_id)
	if blueprint == null:
		return EcsWorld.NO_ENTITY

	var id := world.create_entity()

	# Identity and place come from the placement rather than the blueprint —
	# every entity has both, and neither is a property of its type.
	var named := EcsNameComponent.new()
	named.entity_name = entity_name if entity_name != &"" else StringName("%s_%d" % [type_id, _serial])
	named.type_id = type_id
	named.display_name = blueprint.display_name
	named.uid = new_uid()
	world.add(id, named)
	var position := EcsPositionComponent.new()
	position.position = pos
	world.add(id, position)
	_serial += 1

	for template in blueprint.components:
		if template == null:
			continue
		# Deep-copied per instance. Without this every entity of a type shares
		# one component object and a single override silently rewrites all of
		# them — thirty entities behaving as one entity in thirty bodies.
		var component: EcsComponent = template.duplicate(true)
		var slot_overrides: Variant = _overrides_for(overrides, component.key())
		if slot_overrides is Dictionary:
			_apply_overrides(component, slot_overrides)
		world.add(id, component)

	_build_nodes(world, id, pos)
	return id

## Destroys an entity outright — component data and nodes together.
##
## A berry being picked up *is* killed now: EcsPickupSystem keeps an
## EcsItemRecord of it and flags it Dying, and it comes back, as itself with
## its uid, only if the record is put back into the world.
func kill(world: EcsWorld, id: int) -> void:
	if not world.is_alive(id):
		return
	world.destroy_entity(id)
	_free_nodes(id)

## A fresh identity for a new thing: 128 random bits, as hex.
func new_uid() -> String:
	return _crypto.generate_random_bytes(16).hex_encode()

## The node of `kind` belonging to `id`, or null. This is how a system finds a
## node to update; nothing stores a node handle in a component.
func node_for(id: int, kind: StringName) -> Node2D:
	var owned: Dictionary = _nodes.get(id, {})
	return owned.get(kind)

## The `entity_<id>` container, or null. EcsNodeSyncSystem writes the entity's
## position onto this one node and every child follows.
func container_for(id: int) -> Node2D:
	return _containers.get(id)

## Every entity that currently has nodes. EcsNodeSyncSystem walks this rather
## than a component query: its job is "mirror the data onto the nodes", so the
## nodes are the right thing to iterate, and an entity with no container has
## nothing for it to do.
func entity_ids() -> Array:
	return _containers.keys()

## Drops every node. Called when the world is rebuilt.
func clear() -> void:
	for id: int in _containers.keys():
		_free_nodes(id)
	_containers.clear()
	_nodes.clear()
	_serial = 0

## Reads each component's declared node kind and builds exactly those, once.
##
## Nothing here switches on component *type*: it asks the script for a
## NODE_KIND constant, the same reflective spirit as the inspector reading
## PROPERTY_USAGE_SCRIPT_VARIABLE. A constant rather than a method because a
## component holds data and no behaviour — `const NODE_KIND := EcsConst.NODE_SPRITE`
## is a declaration of intent, and giving one to a new component gets it a node
## without this file being touched.
func _build_nodes(world: EcsWorld, id: int, pos: Vector2) -> void:
	# kind -> the layer policy the component asked for. Collected first so the
	# container is only built if the entity wants anything at all.
	var wanted: Dictionary = {}
	for component in world.components_of(id):
		var kind := node_kind_of(component)
		if kind != &"" and not wanted.has(kind):
			wanted[kind] = Vector2i(
				declared(component, "NODE_LAYER", EcsConst.LAYER_NONE),
				declared(component, "NODE_MASK", EcsConst.LAYER_NONE))
	if wanted.is_empty():
		return

	var container := Node2D.new()
	container.name = "entity_%d" % id
	# Placed at birth, not updated here. An entity must be in the right place
	# the moment it exists — EcsCollisionSystem reads overlaps off the physics
	# server before EcsNodeSyncSystem's first pass, and a container sitting at
	# the origin for one tick would shove everything near (0, 0).	
	container.position = pos
	_root.add_child(container)
	_containers[id] = container

	for kind: StringName in wanted:
		_attach(id, container, kind, wanted[kind])

## The node kind a component declares, or &"" if it implies no node.
static func node_kind_of(component: EcsComponent) -> StringName:
	return declared(component, "NODE_KIND", &"")

## One declaration read off a component's script, or `fallback` if it makes
## none. Constants rather than methods, so a component still holds data and no
## behaviour; this is the same reflective read the inspector does over
## PROPERTY_USAGE_SCRIPT_VARIABLE, one level up.
static func declared(component: EcsComponent, name: String, fallback: Variant) -> Variant:
	var script := component.get_script() as Script
	if script == null:
		return fallback
	return script.get_script_constant_map().get(name, fallback)

func _attach(id: int, container: Node2D, kind: StringName, layers: Vector2i) -> void:
	var node := _make_node(kind, id, layers)
	if node == null:
		return
	# Local zero: the container owns the transform and the children inherit it.
	node.position = Vector2.ZERO
	container.add_child(node)
	var owned: Dictionary = _nodes.get(id, {})
	owned[kind] = node
	_nodes[id] = owned

## Everything here is either the sprite or a circular area, and the area's layer
## policy came from the component, so **this file has no opinion about layers
## and no branch per area kind**. Adding Area2dForSmell is a component with
## three constants and no edit to this function.
##
## Every node is built bare. The values that vary per entity and per tick —
## texture, tint, radius, position — are written by the systems that own them,
## because those are updates and this file only does birth.
func _make_node(kind: StringName, id: int, layers: Vector2i) -> Node2D:
	# `id` is only for the area's back-reference; children are named by kind,
	# because the container they hang under already says which entity they are.
	if kind == EcsConst.NODE_SPRITE:
		var sprite := Sprite2D.new()
		sprite.name = kind
		return sprite
	return _make_area(kind, id, layers.x, layers.y)

## One circular Area2D, bare. `layer` is what others can see of it, `mask` is
## what it can see of others; both are the component's declaration, not this
## file's choice. The radius is left at zero for the system that owns the
## component to write, because a radius is a value and values are updates.
func _make_area(kind: StringName, id: int, layer: int, mask: int) -> EcsEntityArea:
	var area := EcsEntityArea.new()
	area.name = kind
	# The node's back-reference to its row. A typed field rather than metadata,
	# because the systems reading overlaps do this lookup once per neighbour per
	# sensing entity per tick, and a hashed metadata read is not free at that
	# rate. It is an id, not state.
	area.entity_id = id
	# Monitoring finds the overlaps; monitorable lets others find this one.
	# Nothing here pushes anything, so no physics response exists.
	#
	# Declaring a mask is what makes something a looker; declaring a layer is
	# what makes it findable. An area that asked for neither is inert, and that
	# is a legitimate thing to declare.
	area.monitoring = mask != EcsConst.LAYER_NONE
	area.monitorable = layer != EcsConst.LAYER_NONE
	area.collision_layer = layer
	area.collision_mask = mask
	var collider := CollisionShape2D.new()
	collider.name = "Collider"
	collider.shape = CircleShape2D.new()
	area.add_child(collider)
	return area

## One container to free and Godot takes the children with it.
func _free_nodes(id: int) -> void:
	var container: Node2D = _containers.get(id)
	if container != null:
		# Detached before freeing: queue_free() leaves the node parented until
		# the end of the frame, so a respawn in the same frame would double up.
		_root.remove_child(container)
		container.queue_free()
	_containers.erase(id)
	_nodes.erase(id)

func _overrides_for(overrides: Dictionary, component_key: StringName) -> Variant:
	if overrides.has(component_key):
		return overrides[component_key]
	return overrides.get(String(component_key))

func _apply_overrides(component: EcsComponent, overrides: Dictionary) -> void:
	for name_key in overrides:
		var property := StringName(name_key)
		if _has_property(component, property):
			component.set(property, overrides[name_key])
		else:
			push_warning("EcsEntityManager: component '%s' has no property '%s' to override"
				% [component.key(), property])

func _has_property(object: Object, property: StringName) -> bool:
	for entry in object.get_property_list():
		if entry.name == property:
			return true
	return false
