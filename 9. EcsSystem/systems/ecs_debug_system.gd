class_name EcsDebugSystem
extends EcsSystem

## Reads the world and hands a snapshot to the debug overlay. It is a system
## like any other — it holds the behaviour, the views hold none — and it is the
## only one here that is purely a reader: it writes no component and creates no
## entity, so pulling it out of the scheduler changes the simulation not at all.
##
## Run it last, after render, so what it reports is the state that was just drawn.
##
## Note what it does NOT do: it never enumerates an entity's components. It asks
## for the three types it wants to show, by type, exactly as every other system
## does. A fourth component kind would need a column added here — that is the
## honest cost of a hand-written read-out, and the price of not needing any
## reflection machinery to pay it.

var _overlay: EcsDebugOverlay

func _init(overlay: EcsDebugOverlay) -> void:
	_overlay = overlay

func label() -> StringName:
	return &"debug"

func run(world: EcsWorld, _delta: float) -> void:
	if _overlay == null or not _overlay.visible:
		return

	var rows: Array[Dictionary] = []
	for id in world.query([EcsNameComponent, EcsPositionComponent]):
		var named := world.get_component(id, EcsNameComponent) as EcsNameComponent
		var place := world.get_component(id, EcsPositionComponent) as EcsPositionComponent
		var move := world.get_component(id, EcsMovementComponent) as EcsMovementComponent
		var body := world.get_component(id, EcsShapeComponent) as EcsShapeComponent
		var brain := world.get_component(id, EcsLowBrainComponent) as EcsLowBrainComponent

		var row := {
			"id": id,
			"name": named.entity_name,
			"type": named.type_id,
			"pos": place.position,
			"has_movement": move != null,
			"velocity": Vector2.ZERO,
			"heading": 0.0,
			"has_destination": false,
			"destination": Vector2.ZERO,
			"pause_left": 0.0,
			"radius": body.radius if body != null else 0.0,
		}
		if move != null:
			row["velocity"] = move.velocity
			# Screen degrees, 0 = right and increasing clockwise, so the number
			# matches the arrow the overlay draws.
			row["heading"] = fposmod(rad_to_deg(move.velocity.angle()), 360.0)
			row["has_destination"] = move.has_destination
			row["destination"] = move.destination
		if brain != null:
			row["pause_left"] = maxf(brain.pause_left, 0.0)
		rows.append(row)

	_overlay.show_rows(rows)
