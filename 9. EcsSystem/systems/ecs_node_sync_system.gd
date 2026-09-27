class_name EcsNodeSyncSystem
extends EcsSystem

## Mirrors component data onto each entity's nodes, one way, every tick. It is
## the update half of what EcsRenderSystem used to do; the create-and-free half
## went to EcsEntityManager.
##
## Position is written **once per entity**, onto the `entity_<id>` container.
## Its children — the sprite, the body, whatever concerns arrive later — sit at
## local zero and inherit it, so growing a fourth node-backed concern adds no
## work here at all. Only the things that genuinely differ per node, the
## sprite's texture and tint, are written per node.
##
## It walks the manager's entities rather than a component query, because its
## job is "mirror the data onto the nodes" and the nodes are therefore the right
## thing to iterate. An entity with no container has nothing for it to do.
##
## The split from the manager matters more than it looks: the node lives
## exactly as long as the entity, and this system only decides what it shows.
## Nothing is alive-but-nowhere any more — a picked-up berry dies and becomes a
## record — so every container it walks has a position to follow.
##
## Still strictly one-way. Nothing is read back off a node, so the world stays
## true whether or not anything is being drawn — which is what lets the whole
## simulation run headless.

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
