extends CharacterBody2D

@export_category("Param")
@export var movement_speed :int = 100 	
const CELL := 16.0
const HALF  := CELL / 2.0

@export_category("Component")
@export var navigation_agent :NavigationAgent2D 	
@export var main_world: MainWorld

func _ready() -> void:
	# Fine-tune path following feel
	navigation_agent.path_desired_distance = 10.0         # stop re-pathing when close to next corner
	navigation_agent.target_desired_distance = 10.0       # considered “at target” within this radius
	navigation_agent.avoidance_enabled = true            # ready for dynamic obstacle avoidance
	navigation_agent.velocity_computed.connect(_on_velocity_computed)

func _input(event: InputEvent) -> void:
	# this for testing purpose, quickly move playe not new position
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var p: Vector2 = to_local(event.position)
		var new_pos = to_global(snap_to_grid_center(p))
		self.global_position = new_pos
		navigation_agent.target_position = new_pos
		if main_world and main_world.target:
			main_world.target.visible = false
		navigation_agent.set_velocity(Vector2.ZERO)
		move_and_slide()
		return

func snap_to_grid_center(p: Vector2) -> Vector2:
	# Floor to cell index, then add half-cell to land on the center.
	var cell := (p / CELL).floor()
	return cell * CELL + Vector2(HALF, HALF)

func _physics_process(_delta: float) -> void:
	if not main_world or not is_instance_valid(main_world.target) or not main_world.target.visible:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# Always drive the agent toward the current target position (global!)
	navigation_agent.target_position = main_world.target.global_position

	# If we’ve arrived (per target_desired_distance), stop.
	if navigation_agent.is_navigation_finished():
		#main_world.target.visible = false
		navigation_agent.target_position = global_position  # "clear" target
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# Head toward the next path waypoint.
	var next_point: Vector2 = navigation_agent.get_next_path_position()
	var desired_velocity: Vector2 = (next_point - global_position).normalized() * movement_speed

	# Give desired velocity to the agent; it will emit a safe velocity after avoidance.
	navigation_agent.set_velocity(desired_velocity)

func _on_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
	move_and_slide()
	
