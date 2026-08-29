class_name SimFlockTrait
extends SimTrait

## Classic boids, applied only while the brain is wandering: an animal that
## spots food still breaks off to get it.
##
## Flockmates are entities of the SAME blueprint inside the sensor radius, so
## rabbits herd with rabbits and never with berries — and it stays true for any
## future type without naming one.

## How strongly the flock pulls a wander destination. 0 is a plain random walk.
@export_range(0.0, 1.0) var weight: float = 0.55
## Neighbours closer than this push back, which is what stops a flock collapsing
## into a single point.
@export var separation: float = 110.0

## Relative pull of the three urges, blended then clamped to unit length.
@export var cohesion_pull: float = 0.7
@export var separation_pull: float = 1.3
@export var alignment_pull: float = 0.5

func trait_name() -> String:
	return "Flock"

func adjust_wander(brain, offset: Vector2) -> Vector2:
	var steer := _steer(brain)
	if steer == Vector2.ZERO:
		return offset
	return offset.lerp(steer * brain.wander_radius, weight)

func describe(brain) -> Dictionary:
	return {"flockmates": "%d" % _mates(brain).size()}

## Entities of the same blueprint currently in sensor range.
func _mates(brain) -> Array:
	var mates: Array = []
	var sensor: SimSensorComponent = brain.sensor()
	if sensor == null:
		return mates
	for candidate in sensor.get_detected():
		if candidate.def_id == brain.entity.def_id:
			mates.append(candidate)
	return mates

## Cohesion toward the group's centre, separation from anyone crowding, and
## alignment with where the group is already heading.
func _steer(brain) -> Vector2:
	var mates := _mates(brain)
	if mates.is_empty():
		return Vector2.ZERO

	var here: Vector2 = brain.entity.global_position
	var centre := Vector2.ZERO
	var push := Vector2.ZERO
	var heading := Vector2.ZERO
	for mate in mates:
		centre += mate.global_position
		heading += mate.velocity
		var away: Vector2 = here - mate.global_position
		var gap := away.length()
		if gap > 0.0 and gap < separation:
			# Closer neighbours push harder.
			push += (away / gap) * (1.0 - gap / separation)
	centre /= mates.size()

	var cohesion := (centre - here).normalized()
	var alignment := heading.normalized() if heading.length() > 1.0 else Vector2.ZERO
	return (cohesion * cohesion_pull + push.normalized() * separation_pull
		+ alignment * alignment_pull).limit_length(1.0)
