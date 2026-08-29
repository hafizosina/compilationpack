class_name SimBrainComponent
extends SimComponent

## The simple AI. One brain for every creature — what an entity can do is
## decided by which other components it carries, not by brain subclasses.
##
## It owns both behaviours, so nothing has to arbitrate between them:
##   SEEK    something pick-up-able is in sensor range -> walk to it, take it
##   WANDER  nothing in range -> drunkard's walk, one step at a time
##
## Each think tick:
##   1. Forget a target that was taken, freed, or is no longer pick-up-able.
##   2. Ask the sensor for the nearest entity advertising `wanted`.
##   3. In reach -> pick it up. Otherwise walk toward it.
##   4. Nothing in range -> wander.
##
## Step 1 is what makes losing a race harmless: if another animal reaches the
## berry first the target stops being valid, and the next tick retargets to the
## nearest remaining one, or falls back to wandering.

enum State { WANDER, SEEK }

## Seconds between decisions. Cheap enough to run per-entity at this scale.
var think_interval: float = 0.25
## Which affordance the brain goes after.
var wanted: StringName = &"pickupable"

## How far a single wander step may travel from where the entity stands now.
## Destinations are clamped to the painted map, which is the only limit — the
## entity is free to roam the whole world one step at a time.
var wander_radius: float = 420.0
## Seconds idled after arriving, before choosing the next wander destination.
var wander_pause_min: float = 0.3
var wander_pause_max: float = 1.2

## How strongly the flock pulls a wander destination, 0 = pure random walk,
## 1 = ignore the random drift entirely. Flocking applies ONLY while wandering:
## an animal that spots food breaks off and goes to get it.
var flock_weight: float = 0.55
## Neighbours closer than this push back, which is what stops a flock collapsing
## into a single point.
var flock_separation: float = 110.0

## Relative pull of the three classic boid urges, blended then clamped.
const COHESION := 0.7
const SEPARATION := 1.3
const ALIGNMENT := 0.5

var _sensor: SimSensorComponent
var _action: SimActionComponent
var _inventory: SimInventoryComponent
var _movement: SimMovementComponent
var _target: SimEntity
var _state: State = State.WANDER
var _clock: float = 0.0
var _wander_wait: float = 0.0
var _collected: int = 0
var _rng := RandomNumberGenerator.new()

func slot() -> StringName:
	return &"brain"

func _ready() -> void:
	super()
	if entity == null:
		return
	_sensor = entity.get_component(&"sensor") as SimSensorComponent
	_action = entity.get_component(&"action") as SimActionComponent
	_inventory = entity.get_component(&"inventory") as SimInventoryComponent
	_movement = entity.get_component(&"movement") as SimMovementComponent
	if _sensor == null or _movement == null:
		push_warning("SimBrainComponent on '%s' needs a sensor and movement component" % entity.name)
		set_process(false)
		return
	_rng.randomize()
	# Stagger, so a whole population never thinks on the same frame.
	_clock = _rng.randf() * think_interval
	_wander_wait = _rng.randf_range(0.0, wander_pause_max)

func _process(delta: float) -> void:
	_clock -= delta
	if _clock <= 0.0:
		_clock = think_interval
		_think()
	if _state == State.WANDER:
		_step_wander(delta)

func _think() -> void:
	# Nowhere to put anything — no point chasing it, so just roam.
	if _inventory != null and _inventory.is_full():
		_target = null
		_enter(State.WANDER)
		return

	if not _target_is_valid():
		_target = null

	var nearest := _sensor.nearest_with(wanted)
	if nearest != null:
		_target = nearest

	if _target == null:
		_enter(State.WANDER)
		return

	# Reach is asked of the hand; the pick-up itself is asked of the inventory,
	# which owns that action.
	if _action != null and _action.in_reach(_target):
		if _inventory != null and _inventory.try_pick_up(_target):
			_collected += 1
		# Taken by us or beaten to it — either way this target is done with.
		_target = null
		_enter(State.WANDER)
		return

	_enter(State.SEEK)
	_movement.move_to(_target.global_position, SimMovementComponent.Gait.WALK)

func _target_is_valid() -> bool:
	if _target == null or not is_instance_valid(_target):
		return false
	var pickable := _target.get_component(wanted) as SimPickUpAbleComponent
	return pickable != null and pickable.is_available()

func _enter(next: State) -> void:
	if _state == next:
		return
	_state = next
	if next == State.WANDER:
		_movement.stop()

## Drunkard's walk: on arrival, pause a moment, then pick a fresh nearby point.
func _step_wander(delta: float) -> void:
	if _movement.is_moving():
		return
	_wander_wait -= delta
	if _wander_wait > 0.0:
		return
	_wander_wait = _rng.randf_range(wander_pause_min, wander_pause_max)
	_movement.move_to(_wander_point(), SimMovementComponent.Gait.WALK)

## Where to wander next: a random drift, blended with whatever the flock is
## doing. With no flockmates in sight the blend collapses to the plain random
## walk, so a lone animal behaves exactly as before.
##
## The sqrt keeps random points from bunching at the centre; the margin keeps
## destinations off the map edge.
func _wander_point() -> Vector2:
	var angle := _rng.randf_range(0.0, TAU)
	var distance := sqrt(_rng.randf()) * wander_radius
	var drift := Vector2.RIGHT.rotated(angle) * distance
	var flock := _flock_steer()
	var offset := drift if flock == Vector2.ZERO \
		else drift.lerp(flock * wander_radius, flock_weight)
	var point := entity.global_position + offset
	var bounds := SimConst.world_bounds
	var margin := SimConst.EDGE_MARGIN
	return Vector2(
		clampf(point.x, bounds.position.x + margin, bounds.end.x - margin),
		clampf(point.y, bounds.position.y + margin, bounds.end.y - margin)
	)

## Classic boids over the sensor's detections, restricted to the SAME blueprint:
## cohesion toward the group's centre, separation from anyone crowding, and
## alignment with where the group is already heading. Returns a direction of at
## most unit length, or zero when nobody of the same kind is in range.
func _flock_steer() -> Vector2:
	var mates: Array = []
	for candidate in _sensor.get_detected():
		if candidate.def_id == entity.def_id:
			mates.append(candidate)
	if mates.is_empty():
		return Vector2.ZERO

	var centre := Vector2.ZERO
	var push := Vector2.ZERO
	var heading := Vector2.ZERO
	for mate in mates:
		centre += mate.global_position
		heading += mate.velocity
		var away: Vector2 = entity.global_position - mate.global_position
		var gap := away.length()
		if gap > 0.0 and gap < flock_separation:
			# Closer neighbours push harder.
			push += (away / gap) * (1.0 - gap / flock_separation)
	centre /= mates.size()

	var cohesion := (centre - entity.global_position).normalized()
	var alignment := heading.normalized() if heading.length() > 1.0 else Vector2.ZERO
	return (cohesion * COHESION + push.normalized() * SEPARATION
		+ alignment * ALIGNMENT).limit_length(1.0)

## How many entities of this same blueprint are currently in sensor range.
func flockmates() -> int:
	var count := 0
	for candidate in _sensor.get_detected():
		if candidate.def_id == entity.def_id:
			count += 1
	return count

func describe() -> Dictionary:
	var full := _inventory != null and _inventory.is_full()
	return {
		"state": ("wandering (full)" if full else "wandering") if _state == State.WANDER else "seeking",
		"target": _target.name if _target_is_valid() else "—",
		"collected": str(_collected),
		"wander step": "%.0f px" % wander_radius,
		"flockmates": "%d" % flockmates(),
		"thinks every": "%.2f s" % think_interval,
	}
