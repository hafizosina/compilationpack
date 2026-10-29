class_name EcsNodeSyncSystem
extends EcsSystem

## Copies component data onto each entity's nodes every tick: position onto the
## container, appearance onto the sprite. One way; nothing is read back.

var _manager: EcsEntityManager

func _init(manager: EcsEntityManager) -> void:
	_manager = manager

func label() -> StringName:
	return &"node_sync"

func run(world: EcsWorld, _delta: float) -> void:
	if _manager == null:
		return
	for id: int in _manager.entity_ids():
		var container := _manager.container_for(id)
		if container == null:
			continue

		var place := world.get_component(id, EcsPositionComponent) as EcsPositionComponent
		if place == null:
			continue
		container.position = place.position

		var sprite := world.get_component(id, EcsSpriteComponent) as EcsSpriteComponent
		if sprite == null:
			continue
		var view := _manager.node_for(id, EcsConst.NODE_SPRITE) as Sprite2D
		if view == null:
			continue
		view.texture = sprite.texture
		view.scale = Vector2.ONE * sprite.scale_factor
		view.modulate = sprite.tint
		view.z_index = sprite.z_index
