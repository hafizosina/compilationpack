class_name EcsFollowCamera
extends Camera2D

## Module 7's follow camera, fed by EcsPlayerViewSystem instead of reading a player node:
## it sits on the target with a vertical lead toward the facing.

## How far ahead of the facing the camera looks.
@export var lead_distance: float = 200.0
## How quickly the lead eases toward its target (higher = snappier).
@export var lead_smoothing: float = 5.0

var _target: Vector2 = Vector2.ZERO
var _facing: Vector2 = Vector2.RIGHT
var _lead: Vector2 = Vector2.ZERO

## Where to look, and which way the player faces.
func follow(target: Vector2, facing: Vector2) -> void:
	_target = target
	_facing = facing

func _process(delta: float) -> void:
	var target_lead := Vector2(0.0, _facing.normalized().y * lead_distance)
	_lead = _lead.lerp(target_lead, 1.0 - exp(-lead_smoothing * delta))
	global_position = _target + _lead
