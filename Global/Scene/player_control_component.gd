extends Node
class_name PlayerControlComponent

## Shapes analog response to stick distance: 1.0 = linear, >1 = finer control
## near center with a faster ramp toward the edge.
@export var speed_curve: float = 0.9
## The entity this component drives (its facing / rotation / movement).
@export var entity : Entity

@export_group("Dash")
## Speed of the dash burst, in px/s. Distance covered is dash_speed * dash_time.
@export var dash_speed: float = 2000.0
## How long the dash burst lasts.
@export var dash_time: float = 0.15
## Minimum gap between dashes so a held second tap can't chain-dash.
@export var dash_cooldown: float = 0.4
## Two "sprint" presses within this window count as a double-tap dash.
@export var dash_double_tap_window: float = 0.3

var _target_angle: float
# Dash state. _last_sprint_press / _dash_ready_at are absolute times in seconds.
var _last_sprint_press: float = -1.0
var _dash_ready_at: float = 0.0
var _dash_time_left: float = 0.0
var _dash_dir: Vector2 = Vector2.ZERO

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

	# A double-tap of the Sprint button = two quick "sprint" presses = dash.
	_detect_dash(move)
	if _dash_time_left > 0.0:
		_dash(delta)
		return

	_face_dir(aim if aim != Vector2.ZERO else move, delta)
	_move(move, delta)


## Watches for a second "sprint" press within dash_double_tap_window and kicks
## off a dash in the current move direction (falling back to current facing).
func _detect_dash(move: Vector2) -> void:
	if not Input.is_action_just_pressed("sprint"):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_sprint_press <= dash_double_tap_window and now >= _dash_ready_at:
		_dash_dir = move.normalized() if move != Vector2.ZERO else Vector2.from_angle(entity.rotation)
		_dash_time_left = dash_time
		_dash_ready_at = now + dash_time + dash_cooldown
		_last_sprint_press = -1.0  # consume the taps so a third doesn't re-trigger
	else:
		_last_sprint_press = now


## Drives the dash burst; movement and facing are frozen for its duration.
func _dash(delta: float) -> void:
	_dash_time_left -= delta
	entity.position += _dash_dir * dash_speed * delta


## Turn smoothly toward the given direction. Zero is ignored so the entity holds
## its last facing when the joystick is released instead of snapping back to 0.
func _face_dir(dir: Vector2, delta: float) -> void:
	if dir != Vector2.ZERO:
		_target_angle = dir.angle()
	entity.rotation = rotate_toward(entity.rotation, _target_angle, entity.turn_speed * delta)


## Move the entity in world space. dir magnitude (0..1) from the joystick gives
## analog speed, shaped by speed_curve. Movement is independent of facing, so you
## can strafe while aiming.
func _move(dir: Vector2, delta: float) -> void:
	var sprinting := Input.is_action_pressed("sprint")
	# Sprinting ignores sti	ck distance (power) and moves at full speed; otherwise
	# speed scales with how far the stick is pushed, shaped by speed_curve.
	var amount := 1.0 if sprinting else pow(dir.length(), speed_curve)
	var speed := entity.move_speed * (entity.sprint_multiplier if sprinting else 1.0)
	entity.position += dir.normalized() * amount * speed * delta
