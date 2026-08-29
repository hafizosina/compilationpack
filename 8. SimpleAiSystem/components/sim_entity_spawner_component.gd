class_name SimEntitySpawnerComponent
extends SimComponent

## Periodically spawns another entity nearby — a stand-in for the real berry
## bush until harvesting exists.
##
## It never references the factory by node path: the factory puts itself in a
## group, and this looks it up once. What it spawns is a blueprint id, so a
## spawner can produce anything in the catalog without a code change.

## Blueprint id to spawn.
var entity_id: StringName = &"berry"
## Spawns land at a random point within this radius of the spawner.
var radius: float = 220.0
## Seconds between spawns.
var cooldown: float = 1.0
## Ceiling on how many live entities THIS spawner is responsible for. Without a
## cap a one-per-second spawner grows without bound, and every one of them is a
## body that every sensor query has to consider.
var max_alive: int = 40

var _clock: float = 0.0
var _spawned: Array = []
var _factory: SimEntityFactory
var _rng := RandomNumberGenerator.new()

func slot() -> StringName:
	return &"spawner"

func _ready() -> void:
	super()
	_rng.randomize()
	_clock = cooldown

func _process(delta: float) -> void:
	_clock -= delta
	if _clock > 0.0:
		return
	_clock = cooldown
	_spawn_one()

## How many of this spawner's entities are still in the world. Prunes as it goes,
## so collected berries free their slot.
func alive() -> int:
	_spawned = _spawned.filter(func(e): return is_instance_valid(e))
	return _spawned.size()

func _spawn_one() -> void:
	if _factory == null:
		_factory = get_tree().get_first_node_in_group(SimEntityFactory.GROUP) as SimEntityFactory
		if _factory == null:
			push_warning("SimEntitySpawnerComponent found no SimEntityFactory to spawn through")
			return
	if alive() >= max_alive:
		return
	var spawned := _factory.spawn(entity_id, _spawn_point())
	if spawned != null:
		_spawned.append(spawned)

func _spawn_point() -> Vector2:
	var angle := _rng.randf_range(0.0, TAU)
	var distance := sqrt(_rng.randf()) * radius
	var point := entity.global_position + Vector2.RIGHT.rotated(angle) * distance
	var bounds := SimConst.world_bounds
	var margin := SimConst.EDGE_MARGIN
	return Vector2(
		clampf(point.x, bounds.position.x + margin, bounds.end.x - margin),
		clampf(point.y, bounds.position.y + margin, bounds.end.y - margin)
	)

func describe() -> Dictionary:
	return {
		"spawns": String(entity_id),
		"every": "%.1f s" % cooldown,
		"radius": "%.0f px" % radius,
		"alive": "%d / %d" % [alive(), max_alive],
		"next in": "%.1f s" % maxf(_clock, 0.0),
	}
