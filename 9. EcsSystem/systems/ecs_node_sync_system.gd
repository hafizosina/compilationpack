class_name EcsNodeSyncSystem
extends EcsSystem

## Copies component data onto each entity's nodes every tick: position onto the
## container, appearance onto the sprite. One way; nothing is read back.

var _manager: EcsEntityManager

# The working set, rebuilt only when one of these views changes.
var _placed_view: EcsView
var _drawn_view: EcsView
var _places: Array[EcsPositionComponent] = []
var _containers: Array[Node2D] = []
var _sprites: Array[EcsSpriteComponent] = []
var _sprite_nodes: Array[Sprite2D] = []

func _init(manager: EcsEntityManager) -> void:
	_manager = manager

func label() -> StringName:
	return &"node_sync"

func run(world: EcsWorld, _delta: float) -> void:
	if _manager == null:
		return
	_refresh(world)
	for i in _containers.size():
		_containers[i].position = _places[i].position
	for i in _sprite_nodes.size():
		var sprite := _sprites[i]
		var view := _sprite_nodes[i]
		view.texture = sprite.texture
		view.scale = Vector2.ONE * sprite.scale_factor
		view.modulate = sprite.tint
		view.z_index = sprite.z_index

## Rebuilds the working set when entities are born or die.
func _refresh(world: EcsWorld) -> void:
	var placed := world.view([EcsPositionComponent])
	var drawn := world.view([EcsPositionComponent, EcsSpriteComponent])
	if placed == _placed_view and drawn == _drawn_view:
		return
	_placed_view = placed
	_drawn_view = drawn
	_places.clear()
	_containers.clear()
	_sprites.clear()
	_sprite_nodes.clear()

	var places := placed.column(EcsPositionComponent)
	for k in placed.ids.size():
		var container := _manager.container_for(placed.ids[k])
		if container != null:
			_places.append(places[k])
			_containers.append(container)

	var sprites := drawn.column(EcsSpriteComponent)
	for k in drawn.ids.size():
		var node := _manager.node_for(drawn.ids[k], EcsConst.NODE_SPRITE) as Sprite2D
		if node != null:
			_sprites.append(sprites[k])
			_sprite_nodes.append(node)
