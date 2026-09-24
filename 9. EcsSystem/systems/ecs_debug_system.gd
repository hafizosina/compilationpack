class_name EcsDebugSystem
extends EcsSystem

## Reads the world and hands a snapshot to the debug overlay. It is a system
## like any other — it holds the behaviour, the views hold none — and it is the
## only one here that is purely a reader: it writes no component and creates no
## entity, so pulling it out of the scheduler changes the simulation not at all.
##
## Run it last, after node_sync, so what it reports is the state just drawn.
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
		var bag := world.get_component(id, EcsInventoryComponent) as EcsInventoryComponent

		var row := {
			"id": id,
			"name": named.entity_name,
			"type": named.type_id,
			"pos": place.position,
			"has_movement": move != null,
			"velocity": Vector2.ZERO,
			"has_destination": false,
			"destination": Vector2.ZERO,
			"hunger": -1.0,
			"health": -1.0,
			"carried": bag.items.size() if bag != null else -1,
		}
		if move != null:
			row["velocity"] = move.velocity
			row["has_destination"] = move.has_destination
			row["destination"] = move.destination
		# Bars go out as ratios, never as text or pixels. Formatting is the
		# view's business and a fraction is the honest reading — the overlay
		# decides how long a bar that makes, and -1 means "has no such bar".
		var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent
		var health := world.get_component(id, EcsHealthComponent) as EcsHealthComponent
		if hunger != null:
			row["hunger"] = clampf(hunger.fullness / maxf(hunger.max_fullness, 0.01), 0.0, 1.0)
		if health != null:
			row["health"] = clampf(health.value / maxf(health.max_health, 0.01), 0.0, 1.0)
		rows.append(row)

	_overlay.show_rows(rows)
