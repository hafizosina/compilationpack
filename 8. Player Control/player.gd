extends Node2D

func _ready() -> void:
	EventBus.control_dir.connect(_control_dir)
	
	
func _control_dir(dir :Vector2):
	print("Player ",dir)
