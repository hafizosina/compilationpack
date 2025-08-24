extends Node2D
class_name MainWorld

@onready var target: Sprite2D = $Target
const CELL := 16.0
const HALF  := CELL / 2.0

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Convert the click to this node's local space (important if there’s a Camera2D).
			var p: Vector2 = to_local(event.position)
			target.global_position = to_global(snap_to_grid_center(p))
			target.visible = true

func snap_to_grid_center(p: Vector2) -> Vector2:
	# Floor to cell index, then add half-cell to land on the center.
	var cell := (p / CELL).floor()
	return cell * CELL + Vector2(HALF, HALF)
