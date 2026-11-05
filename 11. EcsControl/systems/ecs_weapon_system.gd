class_name EcsWeaponSystem
extends EcsSystem

## Poses each held weapon: at rest beside the facing, across the body while blocking, or along
## its EcsSwingFlag, which it advances and removes when the swing is done. Writes only the pose.

func label() -> StringName:
	return &"weapon"

func run(world: EcsWorld, delta: float) -> void:
	for id in world.query([EcsWeaponComponent]):
		var weapon := world.get_component(id, EcsWeaponComponent) as EcsWeaponComponent
		var player := world.get_component(id, EcsPlayerComponent) as EcsPlayerComponent
		var facing := player.facing.angle() if player != null else 0.0
		var guard := world.get_component(id, EcsBlockingFlag) as EcsBlockingFlag
		weapon.guard_center = facing
		weapon.guard_arc = guard.arc if guard != null else 0.0
		var swing := world.get_component(id, EcsSwingFlag) as EcsSwingFlag
		if swing == null:
			weapon.angle = facing + deg_to_rad(weapon.guard_angle if guard != null else weapon.rest_angle)
			weapon.progress = -1.0
			continue
		swing.elapsed += delta
		var t := clampf(swing.elapsed / maxf(swing.duration, 0.001), 0.0, 1.0)
		var start := swing.direction - deg_to_rad(swing.arc) * 0.5
		weapon.trail_from = start
		weapon.angle = start + deg_to_rad(swing.arc) * ease(t, 0.5)
		weapon.progress = t
		if swing.elapsed >= swing.duration:
			world.remove(id, EcsSwingFlag)
