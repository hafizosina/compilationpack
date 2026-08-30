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

enum State { WANDER, SEEK, FEED }

## Seconds between decisions. Cheap enough to run per-entity at this scale.
var think_interval: float = 0.25
## Which affordance the brain goes after.
var wanted: StringName = &"pickupable"

## Behaviour modifiers, consulted in order at each hook. Empty means default
## behaviour — this is how two entities sharing this one brain end up acting
## differently, with no subclass and no branch in here.
var traits: Array = []

## How far a single wander step may travel from where the entity stands now.
## Destinations are clamped to the painted map, which is the only limit — the
## entity is free to roam the whole world one step at a time.
var wander_radius: float = 420.0
## Seconds idled after arriving, before choosing the next wander destination.
var wander_pause_min: float = 0.3
var wander_pause_max: float = 1.2


var _sensor: SimSensorComponent
var _action: SimActionComponent
var _inventory: SimInventoryComponent
var _hunger: SimHungerComponent
var _movement: SimMovementComponent
var _target: SimEntity
var _state: State = State.WANDER
var _clock: float = 0.0
var _wander_wait: float = 0.0
var _collected: int = 0
var _rng := RandomNumberGenerator.new()

func slot() -> StringName:
	return &"brain"

## Exposed for traits, which reach the world through the brain rather than
## poking at its private members.
func sensor() -> SimSensorComponent:
	return _sensor

func _ready() -> void:
	super()
	if entity == null:
		return
	_sensor = entity.get_component(&"sensor") as SimSensorComponent
	_action = entity.get_component(&"action") as SimActionComponent
	_inventory = entity.get_component(&"inventory") as SimInventoryComponent
	_hunger = entity.get_component(&"hunger") as SimHungerComponent
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
	if _feed_if_hungry():
		return

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

## Hunger takes priority over collecting. Looks in the pocket first because
## that costs no travel, then at the world.
##
## Neither this nor HungerComponent requires an inventory: an entity without one
## simply skips the first half and eats off the ground, which is also what
## happens once its pocket is empty.
func _feed_if_hungry() -> bool:
	if _hunger == null or not _hunger.is_hungry():
		return false

	if _inventory != null:
		var carried := _inventory.find_with_stub(&"consume")
		if carried != null:
			# Nothing to walk to — it is already in hand.
			_hunger.eat(carried)
			_target = null
			_enter(State.WANDER)
			return true

	var found := _sensor.nearest_with_stub(&"consume")
	if found == null:
		return false

	_target = found
	if _action != null and _action.in_reach(found):
		# Eaten where it lies; it never enters the inventory.
		_hunger.eat(found)
		_target = null
		_enter(State.WANDER)
		return true

	_enter(State.FEED)
	_movement.move_to(found.global_position, SimMovementComponent.Gait.WALK)
	return true

func _target_is_valid() -> bool:
	if _target == null or not is_instance_valid(_target):
		return false
	var pickable := _target.get_component(wanted) as SimPickUpAbleComponent
	return pickable != null and pickable.is_available()

func _state_name(full: bool) -> String:
	match _state:
		State.FEED:
			return "going to eat"
		State.SEEK:
			return "seeking"
		_:
			return "wandering (full)" if full else "wandering"

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

## Where to wander next: a random drift, then handed to each trait in turn to
## bend as it sees fit. With no traits the drift is returned untouched.
##
## The sqrt keeps random points from bunching at the centre; the margin keeps
## destinations off the map edge.
func _wander_point() -> Vector2:
	var angle := _rng.randf_range(0.0, TAU)
	var distance := sqrt(_rng.randf()) * wander_radius
	var offset := Vector2.RIGHT.rotated(angle) * distance
	# Each trait gets a say. No traits means the plain random walk survives.
	for behaviour in traits:
		offset = behaviour.adjust_wander(self, offset)
	var point := entity.global_position + offset
	var bounds := SimConst.world_bounds
	var margin := SimConst.EDGE_MARGIN
	return Vector2(
		clampf(point.x, bounds.position.x + margin, bounds.end.x - margin),
		clampf(point.y, bounds.position.y + margin, bounds.end.y - margin)
	)


func describe() -> Dictionary:
	var full := _inventory != null and _inventory.is_full()
	var fields := {
		"state": _state_name(full),
		"target": _target.name if _target_is_valid() else "—",
		"collected": str(_collected),
		"wander step": "%.0f px" % wander_radius,
		"thinks every": "%.2f s" % think_interval,
	}
	var names: Array[String] = []
	for behaviour in traits:
		names.append(behaviour.trait_name())
		var extra: Dictionary = behaviour.describe(self)
		for key in extra:
			fields[key] = extra[key]
	fields["traits"] = ", ".join(names) if not names.is_empty() else "none"
	return fields
