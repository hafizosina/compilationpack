class_name EcsWanderSystem
extends EcsSystem

## A wanderer standing idle waits out its pause, then asks for a path to a random walkable
## cell within its radius. Planning and walking it are EcsPathSystem's and EcsMovementSystem's.

func label() -> StringName:
	return &"wander"

func run(world: EcsWorld, delta: float) -> void:
	var nav := world.get_singleton(EcsTownNavSingleton) as EcsTownNavSingleton
	if nav == null:
		return
	var view := world.view([EcsPositionComponent, EcsMovementComponent, EcsPathComponent, EcsWanderComponent])
	var places := view.column(EcsPositionComponent)
	var moves := view.column(EcsMovementComponent)
	var paths := view.column(EcsPathComponent)
	var wanders := view.column(EcsWanderComponent)
	for k in view.ids.size():
		var path := paths[k] as EcsPathComponent
		if (moves[k] as EcsMovementComponent).has_destination or path.wants or path.next < path.cells.size():
			continue
		var wander := wanders[k] as EcsWanderComponent
		wander.pause_left -= delta
		if wander.pause_left > 0.0:
			continue
		wander.pause_left = randf_range(wander.pause_min, wander.pause_max)
		var from := (places[k] as EcsPositionComponent).position
		var cell := EcsTownGrid.cell_at(from + Vector2.RIGHT.rotated(randf() * TAU) * wander.radius * sqrt(randf()))
		if EcsTownNavSystem.walkable(nav, cell):
			path.goal = cell
			path.wants = true
