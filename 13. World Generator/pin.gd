class_name WorldPin
extends Node2D

## The pin put on L3 where you click: an ochre head on a sepia needle, its point on the spot. Sized with the
## map (the view sets its scale).

func _draw() -> void:
	var ink := WorldMapKey.SEPIA
	draw_colored_polygon(_ellipse(Vector2(0, 0), Vector2(7, 3)), Color(0, 0, 0, 0.25))
	draw_line(Vector2.ZERO, Vector2(0, -22), ink, 2.4, true)
	var head := Vector2(0, -28)
	draw_circle(head, 9.0, WorldMapKey.OCHRE)
	draw_circle(head + Vector2(-2.5, -2.5), 3.0, WorldMapKey.PAPER)
	draw_arc(head, 9.0, 0.0, TAU, 28, ink, 2.0, true)

static func _ellipse(at: Vector2, radius: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for k in 20:
		points.append(at + Vector2.from_angle(k * TAU / 20.0) * radius)
	return points
