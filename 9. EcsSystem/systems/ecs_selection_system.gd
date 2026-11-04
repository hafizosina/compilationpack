class_name EcsSelectionSystem
extends EcsSystem

## Resolves a click, a drag box or an id into EcsSelectedFlags: a click or id
## selects one, shift toggles one, a box selects what it holds (shift adds). Also draws
## the selection marks.

var _marker: EcsSelectionMarker

func _init(marker: EcsSelectionMarker) -> void:
	_marker = marker

func label() -> StringName:
	return &"selection"

func run(world: EcsWorld, _delta: float) -> void:
	var request := world.get_singleton(EcsSelectionSingleton) as EcsSelectionSingleton
	if request != null and request.pending:
		request.pending = false
		if request.pick_id != EcsWorld.NO_ENTITY:
			_click(world, request.pick_id if world.is_alive(request.pick_id) else EcsWorld.NO_ENTITY,
				request.additive)
			request.pick_id = EcsWorld.NO_ENTITY
		elif request.is_box:
			_select_box(world, Rect2(request.pick_at, Vector2.ZERO).expand(request.drag_to),
				request.additive)
		else:
			_click(world, _entity_at(world, request.pick_at), request.additive)
	_draw_marker(world)

func _click(world: EcsWorld, id: int, additive: bool) -> void:
	if not additive:
		_clear(world)
		if id != EcsWorld.NO_ENTITY:
			world.add(id, EcsSelectedFlag.new())
		return
	if id == EcsWorld.NO_ENTITY:
		return
	if world.has(id, EcsSelectedFlag):
		world.remove(id, EcsSelectedFlag)
	else:
		world.add(id, EcsSelectedFlag.new())

func _select_box(world: EcsWorld, box: Rect2, additive: bool) -> void:
	if not additive:
		_clear(world)
	for id in world.query([EcsPositionComponent, EcsSpriteComponent], [EcsSelectedFlag]):
		if box.has_point((world.get_component(id, EcsPositionComponent) as EcsPositionComponent).position):
			world.add(id, EcsSelectedFlag.new())

func _clear(world: EcsWorld) -> void:
	for previous in world.query([EcsSelectedFlag]):
		world.remove(previous, EcsSelectedFlag)

## The entity under `world_position`, or NO_ENTITY for bare ground.
func _entity_at(world: EcsWorld, world_position: Vector2) -> int:
	var closest := EcsWorld.NO_ENTITY
	var closest_distance := INF
	for id in world.query([EcsPositionComponent, EcsSpriteComponent]):
		var here := (world.get_component(id, EcsPositionComponent) as EcsPositionComponent).position
		var distance := here.distance_to(world_position)
		if distance > _hit_radius(world.get_component(id, EcsSpriteComponent) as EcsSpriteComponent):
			continue
		if distance < closest_distance:
			closest_distance = distance
			closest = id
	return closest

func _hit_radius(sprite: EcsSpriteComponent) -> float:
	if sprite.texture == null:
		return 0.0
	return sprite.texture.get_size().x * sprite.scale_factor * 0.5

func _draw_marker(world: EcsWorld) -> void:
	if _marker == null:
		return
	var points := PackedVector2Array()
	var reaches := PackedFloat32Array()
	for id in world.query([EcsSelectedFlag, EcsPositionComponent]):
		points.append((world.get_component(id, EcsPositionComponent) as EcsPositionComponent).position)
		# Ring at the body radius; no body draws just the dot.
		var shape := world.get_component(id, EcsBodyComponent) as EcsBodyComponent
		reaches.append(0.0 if shape == null else shape.radius)
	_marker.show_marks(points, reaches)
