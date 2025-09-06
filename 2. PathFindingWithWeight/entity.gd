extends CharacterBody2D

@export_category("Params")
@export var movement_speed: int = 100

@export_category("Components")
@export var navigation_agent: NavigationAgent2D
@export var main_world: MainWorld

const CELL := 16.0
const HALF := CELL / 2.0

func _ready() -> void:
	# Smoother, cheaper replanning
	navigation_agent.path_desired_distance = 10.0
	navigation_agent.target_desired_distance = 10.0
	navigation_agent.avoidance_enabled = true
	navigation_agent.velocity_computed.connect(_on_velocity_computed)

func _input(event: InputEvent) -> void:
	# Quick test: right-click to snap-teleport and make that your new target
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var local_click: Vector2 = to_local(event.position)
		var snapped_local := snap_to_grid_center(local_click)
		var snapped_global := to_global(snapped_local)

		global_position = snapped_global
		navigation_agent.set_velocity(Vector2.ZERO)
		navigation_agent.target_position = snapped_global  # keep the agent in sync

		if main_world and main_world.target:
			main_world.target.visible = false

		velocity = Vector2.ZERO
		move_and_slide()
		return

func snap_to_grid_center(p: Vector2) -> Vector2:
	return (p / CELL).floor() * CELL + Vector2(HALF, HALF)

func _physics_process(_dt: float) -> void:
	if not main_world or not is_instance_valid(main_world.target) or not main_world.target.visible:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# Always steer toward the current global target
	navigation_agent.target_position = main_world.target.global_position

	if navigation_agent.is_navigation_finished():
		# Keep target equal to current position to avoid churn
		navigation_agent.target_position = global_position
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# Read the next waypoint; this does NOT trigger a new path calculation
	var next_point: Vector2 = navigation_agent.get_next_path_position()
	var desired_velocity := (next_point - global_position).normalized() * movement_speed
	navigation_agent.set_velocity(desired_velocity)

func _on_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
	move_and_slide()
	
