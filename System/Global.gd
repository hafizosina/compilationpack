extends Node

var camera_position: Vector2 = Vector2.ZERO
var camera_zoom: float = 1.0

# Camera-related helper functions
func set_camera_state(position: Vector2, zoom_level: float):
	camera_position = position
	camera_zoom = zoom_level

func get_camera_state() -> Dictionary:
	return {
		"position": camera_position,
		"zoom": camera_zoom
	}
