extends CharacterBody2D

@export_category("Param")
@export var movement_speed :int = 50 	

@export_category("Component")
@export var navigation_agent :NavigationAgent2D 	



func _physics_process(delta: float) -> void:
	if navigation_agent!=null:
		var mouse_pos = get_global_mouse_position()
		navigation_agent.target_position = mouse_pos
		var current_agent_position = self.global_position
		var next_path_pos = navigation_agent.get_next_path_position()
		var new_velocity = current_agent_position.direction_to(next_path_pos) * movement_speed

		if navigation_agent.is_navigation_finished():
			return
		
		if navigation_agent.avoidance_enabled:
			navigation_agent.set_velocity(new_velocity)
		else:
			_on_navigation_agent_2d_velocity_computed(new_velocity)
		move_and_slide()

func _on_navigation_agent_2d_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
