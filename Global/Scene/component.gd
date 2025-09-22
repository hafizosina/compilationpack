extends Node2D
class_name EntityComponent

var entity: Entity

func _ready() -> void:
	print("EntityComponent ready")
	var parent_temp = get_parent()
	if parent_temp is Entity:
		entity = parent_temp
