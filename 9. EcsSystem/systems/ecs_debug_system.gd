class_name EcsDebugSystem
extends EcsSystem

## Sends a per-entity snapshot to the debug overlay. Read only. Bars are
## ratios; -1 means the entity has no such reading.

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
			"energy": -1.0,
			"health": -1.0,
			# 0 awake, 1 asleep, 2 collapsed.
			"sleep": 2 if world.has(id, EcsCollapsedFlag)
				else (1 if world.has(id, EcsAsleepFlag) else 0),
			"carried": bag.items.size() if bag != null else -1,
			# Sprite scale relative to the default.
			"sprite_scale": 1.0,
		}
		var sprite := world.get_component(id, EcsSpriteComponent) as EcsSpriteComponent
		if sprite != null:
			row["sprite_scale"] = sprite.scale_factor / EcsConst.SPRITE_SCALE
		if move != null:
			row["velocity"] = move.velocity
			row["has_destination"] = move.has_destination
			row["destination"] = move.destination
		var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent
		var energy := world.get_component(id, EcsEnergyComponent) as EcsEnergyComponent
		var health := world.get_component(id, EcsHealthComponent) as EcsHealthComponent
		if hunger != null:
			row["hunger"] = clampf(hunger.fullness / maxf(hunger.max_fullness, 0.01), 0.0, 1.0)
		if energy != null:
			row["energy"] = clampf(energy.value / maxf(energy.max_energy, 0.01), 0.0, 1.0)
		if health != null:
			row["health"] = clampf(health.value / maxf(health.max_health, 0.01), 0.0, 1.0)
		rows.append(row)

	_overlay.show_rows(rows)
