# selection_manager.gd
extends Node2D
class_name SelectionManager

var selecting : bool = false
var drag_start : Vector2 = Vector2.ZERO
var select_box : Rect2
var append_selection : bool = false # toggle when presss shift
var already_selected : Array[Node] = []

func _input(event: InputEvent) -> void:
	
	if event is InputEventKey and event.keycode == KEY_SHIFT:
		append_selection = event.pressed
		if event.pressed :
			already_selected = get_tree().get_nodes_in_group("selected").duplicate()
		else:
			already_selected.clear()
	
	if event is InputEventMouseButton : 
		var event_pos = Utils.screen_to_world_position(event.position)
		if  event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				selecting = true
				drag_start = event_pos
			else :
				if drag_start.is_equal_approx(event_pos):
					select_box = Rect2(event_pos, Vector2.ZERO)
				_update_selected_unit()
				queue_redraw()
				selecting = false
	elif event is InputEventMouseMotion:
		var event_pos = Utils.screen_to_world_position(event.position)
		select_box = Rect2(drag_start, event_pos - drag_start).abs()
		queue_redraw()
		_update_selected_unit()
		
		
func _draw() -> void:
	if selecting:
		draw_rect(select_box, Color(0.3, 0.5, 1.0, 0.2))
		draw_rect(select_box, Color(0.3, 0.5, 1.0, 1.0), false, 2.0)

func _update_selected_unit():
	if not selecting: return

	var select_able_component = get_tree().get_nodes_in_group("select_able")

	if append_selection:
		# exclude already selected from processing (they won't be deselected)
		select_able_component = select_able_component.filter(
			func(c): return not (c in already_selected)
		)

	for component in select_able_component:
		if component is SelectAbleComponent:
			var inside: bool = component.is_inside_box(select_box)
			if inside:
				component.select()
			else:
				component.deselect()





		
