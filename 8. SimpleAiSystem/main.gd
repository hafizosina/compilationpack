extends Node2D

## Module 8 entry point. Builds the whole world from data on startup — every
## entity on screen comes out of world1.tres via the SimEntityFactory.
##
## Left-click an entity to inspect it in the bottom-left panel; the selected
## entity also shows its sensor and reach radii. Click bare ground to clear.
## F1 toggles
## the per-entity debug labels, F5 respawns the world (edit world1.tres, hit
## F5, see the change without touching code).

## Physics layer entities sit on, and the layer picking queries against.
const SELECT_MASK := 1
## Ceiling on overlapping bodies considered by one pick.
const MAX_PICK_HITS := 32
## How often the selected entity's snapshot is pushed to the panel. The values
## are read by a person, so 5 Hz is plenty and costs nothing.
const INSPECT_INTERVAL := 0.2

@onready var factory: SimEntityFactory = $EntityFactory
@onready var selection_marker: SimSelectionMarker = $World/SelectionMarker

var _selected: SimEntity
var _since_push: float = 0.0

func _ready() -> void:
	# Read the painted area off the tilemap, so repainting the map moves the
	# wander bounds with it and there is no constant to keep in sync.
	SimConst.adopt_bounds_from($World/TileMapLayer)
	EventBus.sim_respawn_requested.connect(_respawn)
	_respawn()
	_loop_probe()

func _loop_probe() -> void:
	await get_tree().create_timer(0.5).timeout
	for step in 13:
		await get_tree().create_timer(15.0).timeout
		var alive := 0; var dead := 0; var asleep := 0
		var hu := 0.0; var he := 0.0
		var eaten := 0; var berries := 0
		for c in $World/Entities.get_children():
			if c.def_id == &"berry":
				berries += 1
			elif c.def_id == &"animal":
				var h := c.get_component(&"health") as SimHealthComponent
				he += h.value
				hu += (c.get_component(&"hunger") as SimHungerComponent).value
				eaten += (c.get_component(&"brain") as SimBrainComponent)._collected
				if c.is_sleeping: asleep += 1
				if h.is_dead(): dead += 1
				else: alive += 1
		var n := maxf(float(alive + dead), 1.0)
		print("[probe] t=%3ds hp=%5.1f hun=%5.1f | eaten=%2d berries=%2d alive=%d asleep=%d dead=%d"
			% [(step + 1) * 15, he / n, hu / n, eaten, berries, alive, asleep, dead])
	get_tree().quit()

func _process(delta: float) -> void:
	if _selected == null:
		return
	if not is_instance_valid(_selected):
		_select(null)
		return
	_since_push += delta
	if _since_push >= INSPECT_INTERVAL:
		_since_push = 0.0
		EventBus.sim_entity_inspected.emit(_selected.describe())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select(_entity_at(get_global_mouse_position()))
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_F1:
			SimDebugComponent.mode = ((SimDebugComponent.mode + 1)
				% SimDebugComponent.Mode.size()) as SimDebugComponent.Mode
			get_viewport().set_input_as_handled()
		KEY_F5:
			_respawn()
			get_viewport().set_input_as_handled()

## The entity under `world_pos`, or null for bare ground. Picks against the
## entity's own physics body — the same shape a Phase 2 sensor will detect,
## so there is no second set of hitboxes to keep in sync.
##
## Entities overlap freely (nothing collides), and intersect_point returns hits
## in no particular order, so the nearest centre wins. Without that, clicking a
## creature standing on a bush selects whichever the physics server happened to
## report first.
func _entity_at(world_pos: Vector2) -> SimEntity:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = world_pos
	query.collision_mask = SELECT_MASK
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var closest: SimEntity = null
	var closest_distance := INF
	for hit in get_world_2d().direct_space_state.intersect_point(query, MAX_PICK_HITS):
		var collider: Object = hit.get("collider")
		if not (collider is SimEntity):
			continue
		var entity: SimEntity = collider
		var distance := entity.global_position.distance_squared_to(world_pos)
		if distance < closest_distance:
			closest_distance = distance
			closest = entity
	return closest

func _select(entity: SimEntity) -> void:
	_selected = entity
	_since_push = 0.0
	selection_marker.track(entity)
	EventBus.sim_entity_inspected.emit(entity.describe() if entity != null else {})

func _respawn() -> void:
	# Dropped before the spawn frees anything, so nothing holds a dead entity.
	_select(null)
	factory.spawn_world()
	if Constant.DEBUG:
		factory.debug_report()
