extends Camera2D

## How far ahead of the player (in its facing direction) the camera looks.
@export var lead_distance: float = 200.0
## How quickly the lead offset eases toward its target (higher = snappier).
@export var lead_smoothing: float = 5.0

@export var player: Entity

var _lead: Vector2 = Vector2.ZERO

func _ready() -> void:
	if player == null:
		push_error("Camera2D has no player assigned")
		set_process(false)
		return

func _process(delta: float) -> void:
	# Base follow snaps exactly to the player; only the vertical (up/down) lead
	# offset eases smoothly toward its target as facing changes.
	var forward := Vector2.RIGHT.rotated(player.rotation)
	var target_lead := Vector2(0.0, forward.y * lead_distance)
	_lead = _lead.lerp(target_lead, 1.0 - exp(-lead_smoothing * delta))
	global_position = player.global_position + _lead
