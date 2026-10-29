class_name EcsEnergySystem
extends EcsSystem

## Drains energy while awake (more while moving) and restores it while asleep.
## At zero it adds EcsCollapsedFlag and costs health once; the flag lifts at
## `collapse_release`.

func label() -> StringName:
	return &"energy"

func run(world: EcsWorld, delta: float) -> void:
	# Movement and health are optional, so they are looked up.
	var bars := world.view([EcsEnergyComponent])
	var energies := bars.column(EcsEnergyComponent)
	for k in bars.ids.size():
		var id := bars.ids[k]
		var energy := energies[k] as EcsEnergyComponent
		if not energy.rolled:
			# Roll the starting energy on first sight.
			energy.value = energy.max_energy * randf_range(energy.start_min, energy.start_max)
			energy.rolled = true
		var collapsed := world.has(id, EcsCollapsedFlag)
		var resting := collapsed or world.has(id, EcsAsleepFlag)

		if resting:
			energy.value = minf(energy.value + energy.restore * delta, energy.max_energy)
		else:
			var move := world.get_component(id, EcsMovementComponent) as EcsMovementComponent
			var cost := energy.drain_idle
			if move != null and move.velocity.length_squared() > 0.01:
				cost += energy.drain_moving
			energy.value = maxf(energy.value - cost * delta, 0.0)

		if not collapsed and energy.value <= 0.0:
			# Collapse once; the flag prevents repeating it.
			world.add(id, EcsCollapsedFlag.new())
			var health := world.get_component(id, EcsHealthComponent) as EcsHealthComponent
			if health != null:
				health.value = maxf(health.value - energy.collapse_damage, 0.0)
		elif collapsed and energy.value >= energy.collapse_release:
			world.remove(id, EcsCollapsedFlag)
