class_name EcsWeaponView
extends Node2D

## Draws the player's weapon at the pose EcsPlayerViewSystem hands it, and the swing's trail.
## Keeps no clock: every value comes from EcsWeaponComponent.

## Pixel row of the grip in the texture, from the top; the hand holds it there.
@export var grip_row: float = 54.0
@export var trail_color: Color = Color(1.0, 0.97, 0.85, 0.55)

var _sprite: Sprite2D
var _reach: float = 0.0
var _trail_from: float = 0.0
var _angle: float = 0.0
var _progress: float = -1.0
var _guard_center: float = 0.0
var _guard_arc: float = 0.0
@export var guard_color: Color = Color(0.75, 0.9, 1.0, 0.45)
## Radius of the drawn guard.
@export var guard_radius: float = 30.0

func _ready() -> void:
	_sprite = Sprite2D.new()
	add_child(_sprite)

## Places the weapon: `at` the entity's centre, the blade pointing along `angle`.
func show_pose(at: Vector2, weapon: EcsWeaponComponent) -> void:
	position = at
	if _sprite.texture != weapon.texture:
		_sprite.texture = weapon.texture
	if weapon.texture != null:
		var half := weapon.texture.get_height() * 0.5
		_sprite.offset = Vector2(0.0, half - grip_row)
		_reach = weapon.hold + (grip_row - 4.0) * weapon.scale_factor
	_sprite.scale = Vector2.ONE * weapon.scale_factor
	_sprite.rotation = weapon.angle + PI * 0.5
	_sprite.position = Vector2.from_angle(weapon.angle) * weapon.hold
	if _progress >= 0.0 or weapon.progress >= 0.0 or _guard_arc > 0.0 or weapon.guard_arc > 0.0:
		_trail_from = weapon.trail_from
		_angle = weapon.angle
		_progress = weapon.progress
		_guard_center = weapon.guard_center
		_guard_arc = weapon.guard_arc
		queue_redraw()

func _draw() -> void:
	if _guard_arc > 0.0:
		var half := deg_to_rad(_guard_arc) * 0.5
		draw_arc(Vector2.ZERO, guard_radius, _guard_center - half, _guard_center + half, 24, guard_color, 5.0, true)
	if _progress < 0.0 or is_equal_approx(_angle, _trail_from):
		return
	var fade := trail_color
	fade.a *= 1.0 - _progress * 0.6
	draw_arc(Vector2.ZERO, _reach, _trail_from, _angle, 24, fade, 6.0, true)
