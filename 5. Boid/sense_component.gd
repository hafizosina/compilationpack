extends EntityComponent
class_name SenseComponent

@onready var sense_area: CollisionShape2D = %CollisionShape2D


func _ready() -> void:
	super._ready() 
	print("SenseComponent ready")
	if entity!=null:
		var sense_shape := CircleShape2D.new()
		sense_shape.radius = entity.size * 10
		sense_area.shape = sense_shape
		
