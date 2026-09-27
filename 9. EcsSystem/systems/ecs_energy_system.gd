class_name EcsEnergySystem
extends EcsSystem

## Energy drains while awake, comes back while asleep, and running out drops the
## entity where it stands.
##
## It owns the consequences of energy the way EcsHungerSystem owns the
## consequences of fullness: it writes `value`, the collapse tag, and the health
## a collapse costs. It never writes the brain or movement.
##
## **Sleeping is a decision; this is what makes it mean something.** The brain
## raises EcsAsleepFlag and this reads the flag to switch drain for restore — the same executor shape EcsConsumeSystem uses for EAT, except that
## eating is one act and resting is a rate.
##
## Collapse is the other direction: at zero this adds EcsCollapsedFlag, and
## the brain reads the tag and stops deciding. Two systems, one component each,
## no calls between them.
##
## It sits beside `hunger` in the pipeline so a collapse's damage and any death
## that follows land in the same tick. It reads the flag as the brain last left
## it — and the brain runs at 20 Hz — so restoring begins up to
## three ticks after SLEEP is chosen. That is invisible, and it is written down
## here so nobody "fixes" it by moving the stage.

func label() -> StringName:
	return &"energy"

func run(world: EcsWorld, delta: float) -> void:
	for id in world.query([EcsEnergyComponent]):
		var energy := world.get_component(id, EcsEnergyComponent) as EcsEnergyComponent
		var collapsed := world.has(id, EcsCollapsedFlag)
		var resting := collapsed or world.has(id, EcsAsleepFlag)

		if resting:
			energy.value = minf(energy.value + energy.restore * delta, energy.max_energy)
		else:
			# Moving costs more than standing, and `velocity` is what movement
			# left behind — no system has to be told whether it walked.
			var move := world.get_component(id, EcsMovementComponent) as EcsMovementComponent
			var cost := energy.drain_idle
			if move != null and move.velocity.length_squared() > 0.01:
				cost += energy.drain_moving
			energy.value = maxf(energy.value - cost * delta, 0.0)

		if not collapsed and energy.value <= 0.0:
			# Crossing into empty, once. The tag is what stops it happening
			# again next tick, so the damage cannot be paid twice.
			world.add(id, EcsCollapsedFlag.new())
			var health := world.get_component(id, EcsHealthComponent) as EcsHealthComponent
			if health != null:
				health.value = maxf(health.value - energy.collapse_damage, 0.0)
		elif collapsed and energy.value >= energy.collapse_release:
			# Come round, still tired. It goes on sleeping of its own accord
			# from here, which is what makes starving able to wake it.
			world.remove(id, EcsCollapsedFlag)
