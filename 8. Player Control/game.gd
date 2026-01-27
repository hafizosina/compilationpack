extends Node2D

@onready var camera_2d: Camera2D = $Camera2D
@onready var player: Node2D = $Player

func _process(delta: float) -> void:
	camera_2d.position = player.position
	
