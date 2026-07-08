extends Node
class_name PlayerControlComponent

## How fast the entity turns toward its facing direction (radians per second).
@export var turn_speed: float = 12.0
## How fast the entity moves, in pixels per second.
@export var move_speed: float = 400.0
## Shapes analog response to stick distance: 1.0 = linear, >1 = finer control
## near center with a faster ramp toward the edge.
@export var speed_curve: float = 2.0
## Speed multiplier applied while the sprint button is held.
@export var sprint_multiplier: float = 1.8
## The entity this component drives (its facing / rotation / movement).
@export var entity : Entity

var _target_angle: float

func _ready() -> void:
	if entity == null:
		push_error("PlayerControlComponent has no entity assigned")
		set_process(false)
		return
	_target_angle = entity.rotation

func _process(delta: float) -> void:
	# Movement comes from the left joystick; facing prefers the aim joystick and
	# falls back to the movement direction when not aiming.
	# Explicit low deadzone so small stick movements register. Without it,
	# get_vector uses the ui_* actions' 0.5 deadzone and the player only moves
	# once the stick passes ~50% of its radius.
	var move := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down", 0.05)
	var aim := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	_face_dir(aim if aim != Vector2.ZERO else move, delta)
	_move(move, delta)


## Turn smoothly toward the given direction. Zero is ignored so the entity holds
## its last facing when the joystick is released instead of snapping back to 0.
func _face_dir(dir: Vector2, delta: float) -> void:
	if dir != Vector2.ZERO:
		_target_angle = dir.angle()
	entity.rotation = rotate_toward(entity.rotation, _target_angle, turn_speed * delta)


## Move the entity in world space. dir magnitude (0..1) from the joystick gives
## analog speed, shaped by speed_curve. Movement is independent of facing, so you
## can strafe while aiming.
func _move(dir: Vector2, delta: float) -> void:
	var sprinting := Input.is_action_pressed("sprint")
	# Sprinting ignores stick distance (power) and moves at full speed; otherwise
	# speed scales with how far the stick is pushed, shaped by speed_curve.
	var amount := 1.0 if sprinting else pow(dir.length(), speed_curve)
	var speed := move_speed * (sprint_multiplier if sprinting else 1.0)
	entity.position += dir.normalized() * amount * speed * delta
