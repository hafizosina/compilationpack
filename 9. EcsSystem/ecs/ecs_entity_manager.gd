class_name EcsEntityManager
extends RefCounted

## The only code that creates or destroys entities, their components and their
## nodes. It never updates nodes; EcsNodeSyncSystem and EcsCollisionSystem do.
##
## Each entity's nodes live under one container, `World/Entities/entity_<id>/`,
## which carries the transform. A container holds no script and no state.

var _root: Node2D
var _containers: Dictionary = {}  # entity id -> Node2D container
var _nodes: Dictionary = {}       # entity id -> { node kind -> Node2D }
var _serial: int = 0
var _crypto := Crypto.new()

func _init(root: Node2D) -> void:
	_root = root

## Clears all nodes and spawns every placement in `world_def`. Called at startup and on F5.
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

## Clears all nodes and rebuilds the world from a snapshot (EcsSnapshot.capture),
## ids included. Returns false if the data could not be read.
func load_snapshot(world: EcsWorld, data: Dictionary) -> bool:
	var decoded := EcsSnapshot.decode(data)
	if decoded.is_empty():
		return false
	clear()
	var entities: Dictionary = decoded["entities"]
	for id: int in entities:
		if not world.create_entity_with_id(id):
			push_error("EcsEntityManager: snapshot entity %d already exists" % id)
			continue
		for component: EcsComponent in entities[id]:
			world.add(id, component)
	for singleton: EcsComponent in decoded["singletons"]:
		world.add_singleton(singleton)
	world.reserve_ids_below(decoded["next_id"])
	# Numbered names continue past every id, so none repeats.
	_serial = world.next_id()
	for id: int in entities:
		var place := world.get_component(id, EcsPositionComponent) as EcsPositionComponent
		_build_nodes(world, id, place.position if place != null else Vector2.ZERO)
	return true

## Handles pending spawn requests, then kills everything flagged dying.
## Requests raised during the drain wait for the next tick.
func drain(world: EcsWorld, catalog: EcsEntityCatalog) -> void:
	var inbox := world.get_singleton(EcsLifecycleSingleton) as EcsLifecycleSingleton
	if inbox == null:
		return

	var births := inbox.spawn_requests
	inbox.spawn_requests = []
	for request in births:
		if request.record != null:
			request.born = restore(world, request.record, request.position)
		else:
			request.born = spawn(world, catalog, request.type_id, request.position,
				request.overrides, request.entity_name)
		request.fulfilled = true

	for id in world.query([EcsDyingFlag]):
		kill(world, id)

## Builds one entity of `type_id` at `pos` and returns its id, or NO_ENTITY.
func spawn(world: EcsWorld, catalog: EcsEntityCatalog, type_id: StringName, pos: Vector2,
		overrides: Dictionary = {}, entity_name: StringName = &"") -> int:
	var blueprint := catalog.get_def(type_id)
	if blueprint == null:
		return EcsWorld.NO_ENTITY

	var id := world.create_entity()

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
		# Copy per instance, or every entity of a type shares one component.
		var component: EcsComponent = template.duplicate(true)
		var slot_overrides: Variant = _overrides_for(overrides, component.key())
		if slot_overrides is Dictionary:
			_apply_overrides(component, slot_overrides)
		world.add(id, component)

	_build_nodes(world, id, pos)
	return id

## Puts a carried item back into the world at `pos`. Keeps its components and
## uid; gets a new id.
func restore(world: EcsWorld, record: EcsItemRecord, pos: Vector2) -> int:
	var id := world.create_entity()
	for component in record.components:
		world.add(id, component)
	var place := world.get_component(id, EcsPositionComponent) as EcsPositionComponent
	if place == null:
		place = world.add(id, EcsPositionComponent.new()) as EcsPositionComponent
	place.position = pos
	_build_nodes(world, id, pos)
	return id

## Destroys an entity's data and nodes.
func kill(world: EcsWorld, id: int) -> void:
	if not world.is_alive(id):
		return
	world.destroy_entity(id)
	_free_nodes(id)

## A new random 128-bit id, as hex.
func new_uid() -> String:
	return _crypto.generate_random_bytes(16).hex_encode()

## The node of `kind` belonging to `id`, or null.
func node_for(id: int, kind: StringName) -> Node2D:
	var owned: Dictionary = _nodes.get(id, {})
	return owned.get(kind)

## The `entity_<id>` container, or null.
func container_for(id: int) -> Node2D:
	return _containers.get(id)

## Every entity that has nodes.
func entity_ids() -> Array:
	return _containers.keys()

## Drops every node. Called when the world is rebuilt.
func clear() -> void:
	for id: int in _containers.keys():
		_free_nodes(id)
	_containers.clear()
	_nodes.clear()
	_serial = 0

## Builds the nodes the entity's components declare through `NODE_KIND`.
func _build_nodes(world: EcsWorld, id: int, pos: Vector2) -> void:
	var wanted: Dictionary = {}  # kind -> Vector2i(layer, mask)
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
	# Placed now so collision doesn't see it at the origin for one tick.
	container.position = pos
	_root.add_child(container)
	_containers[id] = container

	for kind: StringName in wanted:
		_attach(id, container, kind, wanted[kind])

## The node kind a component declares, or &"".
static func node_kind_of(component: EcsComponent) -> StringName:
	return declared(component, "NODE_KIND", &"")

## A constant from the component's script, or `fallback`.
static func declared(component: EcsComponent, name: String, fallback: Variant) -> Variant:
	var script := component.get_script() as Script
	if script == null:
		return fallback
	return script.get_script_constant_map().get(name, fallback)

func _attach(id: int, container: Node2D, kind: StringName, layers: Vector2i) -> void:
	var node := _make_node(kind, id, layers)
	if node == null:
		return
	node.position = Vector2.ZERO
	container.add_child(node)
	var owned: Dictionary = _nodes.get(id, {})
	owned[kind] = node
	_nodes[id] = owned

## A bare sprite, or a circular area for any other kind. Values are set later
## by the systems that own them.
func _make_node(kind: StringName, id: int, layers: Vector2i) -> Node2D:
	if kind == EcsConst.NODE_SPRITE:
		var sprite := Sprite2D.new()
		sprite.name = kind
		return sprite
	return _make_area(kind, id, layers.x, layers.y)

## A circular area with radius 0. `layer` makes it detectable, `mask` makes it detect.
func _make_area(kind: StringName, id: int, layer: int, mask: int) -> EcsEntityArea:
	var area := EcsEntityArea.new()
	area.name = kind
	area.entity_id = id
	area.monitoring = mask != EcsConst.LAYER_NONE
	area.monitorable = layer != EcsConst.LAYER_NONE
	area.collision_layer = layer
	area.collision_mask = mask
	var collider := CollisionShape2D.new()
	collider.name = "Collider"
	collider.shape = CircleShape2D.new()
	area.add_child(collider)
	return area

func _free_nodes(id: int) -> void:
	var container: Node2D = _containers.get(id)
	if container != null:
		# Detach first; queue_free() keeps it parented until the frame ends.
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
