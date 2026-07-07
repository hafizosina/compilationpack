extends Control

## Health value where the C-arc ends and the horizontal bar begins.
## Health is one 0..100 value shown across two bars: the arc holds 0..split,
## the horizontal bar holds split..100 (so the horizontal half drains first).
@export var health_split: float = 40.0

@onready var _health_arc: TextureProgressBar = $FirstHalfHealthBar
@onready var _health_bar: TextureProgressBar = $EndhalfHealthBar
@onready var _stamina: TextureProgressBar = $StaminaBar
@onready var _mana: TextureProgressBar = $ManaBar

func _ready() -> void:
	_health_arc.min_value = 0.0
	_health_arc.max_value = health_split
	_health_bar.min_value = health_split
	_health_bar.max_value = 100.0

func set_health(value: float) -> void:
	_health_arc.value = clampf(value, 0.0, health_split)
	_health_bar.value = clampf(value, health_split, 100.0)

func set_stamina(value: float) -> void:
	_stamina.value = value

func set_mana(value: float) -> void:
	_mana.value = value
