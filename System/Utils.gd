extends Node

func zoom_scale_ratio(i: float) -> int:
	return int(round(log(i) / log(2))) *1.5
	
	
func screen_to_world_position(screen_pos: Vector2) -> Vector2:
	var camera_state = Global.get_camera_state()
	# Get viewport size
	var viewport = get_viewport()
	var viewport_size = viewport.get_visible_rect().size
	
	# Calculate the center offset
	var center_offset = viewport_size / 2.0
	
	# Convert screen position to camera-relative position
	var camera_relative_pos = (screen_pos - center_offset) / camera_state.zoom
	
	# Add camera position to get world position
	var world_pos = camera_state.position + camera_relative_pos
	
	return world_pos
