class_name EcsRenderSystem
extends EcsSystem

## The one place the scene tree meets the world, and it is one-way: this system
## reads position and sprite data and pushes it onto a pool of Sprite2Ds.
##
## The biggest shift from module 8 lives here. A node is no longer an entity —
## it is a *view* of one, created when an id starts matching the query and freed
## when it stops. Nothing reads back off a node, so the world stays true whether
## or not anything is being drawn (which is also what lets the whole simulation
## run headless).

var _root: Node2D
var _views: Dictionary = {}  # entity_id -> Sprite2D

func _init(root: Node2D) -> void:
	_root = root

func label() -> StringName:
	return &"render"

func run(world: EcsWorld, _delta: float) -> void:
	if _root == null:
		return
	var live: Dictionary = {}
	for id in world.query([EcsPositionComponent, EcsSpriteComponent]):
		live[id] = true
		var view: Sprite2D = _views.get(id)
		if view == null:
			view = Sprite2D.new()
			view.name = "view_%d" % id
			_root.add_child(view)
			_views[id] = view
		var sprite := world.get_component(id, EcsSpriteComponent) as EcsSpriteComponent
		view.texture = sprite.texture
		view.scale = Vector2.ONE * sprite.scale_factor
		view.modulate = sprite.tint
		view.z_index = sprite.z_index
		view.position = (world.get_component(id, EcsPositionComponent) as EcsPositionComponent).position

	for id: int in _views.keys():
		if live.has(id):
			continue
		# Detached before freeing: queue_free() leaves the node parented until
		# the end of the frame, so a respawn in the same frame would double up.
		var view: Sprite2D = _views[id]
		_root.remove_child(view)
		view.queue_free()
		_views.erase(id)

## Drops every view. Called when the world is rebuilt.
func clear() -> void:
	for id: int in _views.keys():
		var view: Sprite2D = _views[id]
		_root.remove_child(view)
		view.queue_free()
	_views.clear()
