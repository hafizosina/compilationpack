@tool
class_name RBoxContainer
extends Container

## Arranges its children evenly on a ring — a radial counterpart to VBox/HBoxContainer.
## Works as a full circle, an arc, or a fan depending on `arc`/`start_angle`.

## Radius of the ring the children sit on, in pixels.
@export var radius: float = 150.0:
	set(v):
		radius = v
		queue_sort()
		update_minimum_size()

## Angle of the FIRST child, degrees, clockwise from +X (0=right, 90=down, 180=left, 270=up).
@export var start_angle: float = 180.0:
	set(v):
		start_angle = v
		queue_sort()

## Total span the children cover, degrees. 360 = full circle; <360 = arc/fan.
@export_range(0.0, 360.0, 0.1) var arc: float = 360.0:
	set(v):
		arc = v
		queue_sort()

## For arc < 360: put the first & last child exactly on the arc endpoints.
## Ignored on a full circle (endpoints would overlap).
@export var include_endpoints: bool = true:
	set(v):
		include_endpoints = v
		queue_sort()

## Size each child is laid out at (their own min size is usually ~0).
@export var item_size: Vector2 = Vector2(120, 120):
	set(v):
		item_size = v
		queue_sort()
		update_minimum_size()

## Rotate each child to face outward along its radius.
@export var orient_to_center: bool = false:
	set(v):
		orient_to_center = v
		queue_sort()


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_sort()


func _visible_children() -> Array:
	var out: Array = []
	for c in get_children():
		var ctrl := c as Control
		if ctrl and ctrl.visible and not ctrl.top_level:
			out.append(ctrl)
	return out


func _sort() -> void:
	var kids := _visible_children()
	var n := kids.size()
	if n == 0:
		return
	var center := size * 0.5
	var span := deg_to_rad(arc)
	# full circle or open arc → divide by n (even gap incl. the closing one);
	# arc with endpoints → divide by n-1 so first & last hit the ends.
	var even := arc >= 360.0 or not include_endpoints or n == 1
	var step := span / n if even else span / (n - 1)
	var base := deg_to_rad(start_angle)
	for i in n:
		var ang := base + step * i
		var pos := center + Vector2(cos(ang), sin(ang)) * radius
		fit_child_in_rect(kids[i], Rect2(pos - item_size * 0.5, item_size))
		kids[i].rotation = ang if orient_to_center else 0.0


func _get_minimum_size() -> Vector2:
	return Vector2(radius, radius) * 2.0 + item_size
