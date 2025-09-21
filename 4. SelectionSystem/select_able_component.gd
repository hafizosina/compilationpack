# select_able_component.gd
extends Node2D
class_name SelectAbleComponent

var entity: Entity
var selected:bool= false
var padding : int = 5

func select() -> void:
	selected = true
	if entity!=null:
		add_to_group("selected")   # ✅ mark as globally selected
		queue_redraw()
		#print(entity.name, "Selected")
		

func deselect() -> void:
	selected = false
	if entity!=null:
		remove_from_group("selected")  # ✅ remove from global selection
		queue_redraw()
		#print(entity.name, "Delected")

func is_inside_box(rect : Rect2) -> bool:
	if entity == null:
		return false
	
	# Circle definition
	var center: Vector2 = global_position
	var radius: float = entity.size + padding

	# Find closest point in rect to circle center
	var closest_x = clamp(center.x, rect.position.x, rect.position.x + rect.size.x)
	var closest_y = clamp(center.y, rect.position.y, rect.position.y + rect.size.y)
	var closest_point = Vector2(closest_x, closest_y)
	# Check distance
	return center.distance_to(closest_point) <= radius

func _ready() -> void:
	var parent_temp = get_parent()
	if parent_temp is Entity:
		entity = parent_temp
		
func _draw() -> void:
	if selected:
		var circle_size = entity.size + padding
		draw_circle(position,circle_size,Color(0.857, 0.0, 0.318, 0.6))
		draw_circle(position,circle_size,Color(0.056, 0.214, 1.0, 1.0), false, 1)
		
		
