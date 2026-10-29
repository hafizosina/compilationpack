class_name EcsSelectionSystem
extends EcsSystem

## Resolves a click to the nearest entity under it, by sprite size, and moves
## EcsSelectedFlag there. Also draws the selection marker.

var _marker: EcsSelectionMarker

func _init(marker: EcsSelectionMarker) -> void:
	_marker = marker

func label() -> StringName:
	return &"selection"

func run(world: EcsWorld, _delta: float) -> void:
	var request := world.get_singleton(EcsSelectionSingleton) as EcsSelectionSingleton
	if request != null and request.pending:
		request.pending = false
		_select(world, _entity_at(world, request.pick_at))
	_draw_marker(world)

## Clears any previous selection and tags `id`, or clears alone when NO_ENTITY.
func _select(world: EcsWorld, id: int) -> void:
	for previous in world.query([EcsSelectedFlag]):
		world.remove(previous, EcsSelectedFlag)
	if id != EcsWorld.NO_ENTITY:
		world.add(id, EcsSelectedFlag.new())

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
	var selected := world.query([EcsSelectedFlag, EcsPositionComponent])
	if selected.is_empty():
		_marker.clear()
		return
	var id: int = selected[0]
	# Ring at the body radius; no body draws just the dot.
	var shape := world.get_component(id, EcsBodyComponent) as EcsBodyComponent
	_marker.show_at(
		(world.get_component(id, EcsPositionComponent) as EcsPositionComponent).position,
		0.0 if shape == null else shape.radius)
