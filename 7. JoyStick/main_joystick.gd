extends Node2D


func _on_virtual_joystick_analogic_changed(value: Vector2, distance: float, angle: float, angle_clockwise: float, angle_not_clockwise: float) -> void:
	print(value)
