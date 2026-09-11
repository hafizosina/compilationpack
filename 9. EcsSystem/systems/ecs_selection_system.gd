class_name EcsSelectionSystem
extends EcsSystem

## Picking, the selection tag, and the marker that shows it.
##
## Module 8 picked with a physics point query against a per-entity Area2D. There
## are no areas here and no second set of hitboxes to keep in sync — a pick is a
## distance test over EcsPositionComponent, which is the plan's point about
## perception and selection both collapsing into queries.
##
## Each candidate's hit radius comes from its own sprite, so the clickable area
## is whatever you can see rather than a constant somebody has to remember to
## update. Entities overlap freely, so the nearest centre wins; without that,
## clicking a monkey holding a dagger selects whichever was stored first.

var _marker: EcsSelectionMarker

func _init(marker: EcsSelectionMarker) -> void:
	_marker = marker

func label() -> StringName:
	return &"selection"

func run(world: EcsWorld, _delta: float) -> void:
	var request := world.get_singleton(EcsSelectionComponent) as EcsSelectionComponent
	if request != null and request.pending:
		request.pending = false
		_select(world, _entity_at(world, request.pick_at))
	_draw_marker(world)

## Clears any previous selection and tags `id`, or clears alone when NO_ENTITY.
func _select(world: EcsWorld, id: int) -> void:
	for previous in world.query([EcsSelectedComponent]):
		world.remove(previous, EcsSelectedComponent)
	if id != EcsWorld.NO_ENTITY:
		world.add(id, EcsSelectedComponent.new())

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
	var selected := world.query([EcsSelectedComponent, EcsPositionComponent])
	if selected.is_empty():
		_marker.clear()
		return
	var id: int = selected[0]
	var aggression := world.get_component(id, EcsAggressionComponent) as EcsAggressionComponent
	_marker.show_at(
		(world.get_component(id, EcsPositionComponent) as EcsPositionComponent).position,
		0.0 if aggression == null else aggression.reach)
