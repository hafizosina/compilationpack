class_name EcsNodeSyncSystem
extends EcsSystem

## Copies component data onto each entity's nodes: position onto the container,
## appearance onto the sprite. One way; nothing is read back. Only movers are
## written every tick; the rest is rewritten when entities come or go, or an edit lands.

var _manager: EcsEntityManager

# The working set, rebuilt only when one of these views changes.
var _placed_view: EcsView
var _moving_view: EcsView
var _drawn_view: EcsView
var _edits_seen: int = -1
var _places: Array[EcsPositionComponent] = []
var _containers: Array[Node2D] = []
var _moving_places: Array[EcsPositionComponent] = []
var _moving_containers: Array[Node2D] = []
var _sprites: Array[EcsSpriteComponent] = []
var _sprite_nodes: Array[Sprite2D] = []

func _init(manager: EcsEntityManager) -> void:
	_manager = manager

func label() -> StringName:
	return &"node_sync"

func run(world: EcsWorld, _delta: float) -> void:
	if _manager == null:
		return
	var edits := world.get_singleton(EcsEditSingleton) as EcsEditSingleton
	var edited := edits.applied if edits != null else 0
	if _refresh(world) or edited != _edits_seen:
		_edits_seen = edited
		_write_all()
		return
	for i in _moving_containers.size():
		_moving_containers[i].position = _moving_places[i].position

## Writes every position and sprite.
func _write_all() -> void:
	for i in _containers.size():
		_containers[i].position = _places[i].position
	for i in _sprite_nodes.size():
		var sprite := _sprites[i]
		var view := _sprite_nodes[i]
		view.texture = sprite.texture
		view.scale = Vector2.ONE * sprite.scale_factor
		view.modulate = sprite.tint
		view.z_index = sprite.z_index

## Rebuilds the working set when entities are born or die; true if it did.
func _refresh(world: EcsWorld) -> bool:
	var placed := world.view([EcsPositionComponent])
	var moving := world.view([EcsPositionComponent, EcsMovementComponent])
	var drawn := world.view([EcsPositionComponent, EcsSpriteComponent])
	if placed == _placed_view and moving == _moving_view and drawn == _drawn_view:
		return false
	_placed_view = placed
	_moving_view = moving
	_drawn_view = drawn
	_places.clear()
	_containers.clear()
	_moving_places.clear()
	_moving_containers.clear()
	_sprites.clear()
	_sprite_nodes.clear()

	var places := placed.column(EcsPositionComponent)
	for k in placed.ids.size():
		var container := _manager.container_for(placed.ids[k])
		if container != null:
			_places.append(places[k])
			_containers.append(container)

	var moving_places := moving.column(EcsPositionComponent)
	for k in moving.ids.size():
		var container := _manager.container_for(moving.ids[k])
		if container != null:
			_moving_places.append(moving_places[k])
			_moving_containers.append(container)

	var sprites := drawn.column(EcsSpriteComponent)
	for k in drawn.ids.size():
		var node := _manager.node_for(drawn.ids[k], EcsConst.NODE_SPRITE) as Sprite2D
		if node != null:
			_sprites.append(sprites[k])
			_sprite_nodes.append(node)
	return true
