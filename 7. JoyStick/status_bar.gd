@tool
extends Control

## Health value where the C-arc ends and the horizontal bar begins.
## Health is one 0..100 value shown across two bars: the arc holds 0..split,
## the horizontal bar holds split..100 (so the horizontal half drains first).
const HEALTH_SPLIT := 40.0

## Current stat values. Exported so they can be previewed live in the editor;
## each setter re-renders the bars. At runtime the EventBus signals feed these.
@export_range(0.0, 100.0, 0.1) var health_value: float = 100.0:
	set(value):
		health_value = value
		_refresh()
@export_range(0.0, 100.0, 0.1) var stamina_value: float = 99.0:
	set(value):
		stamina_value = value
		_refresh()
@export_range(0.0, 100.0, 0.1) var mana_value: float = 100.0:
	set(value):
		mana_value = value
		_refresh()

@onready var _health_arc: TextureProgressBar = $FirstHalfHealthBar
@onready var _health_bar: TextureProgressBar = $EndhalfHealthBar
@onready var _stamina: TextureProgressBar = $StaminaBar
@onready var _mana: TextureProgressBar = $ManaBar

func _ready() -> void:
	_refresh()
	# Only wire the EventBus at runtime; in the editor the exports drive preview.
	if Engine.is_editor_hint():
		return
	EventBus.health_change.connect(set_health)
	EventBus.stamina_change.connect(set_stamina)
	EventBus.mana_change.connect(set_mana)

## Push all current values onto the bars. Guarded so the property setters can
## fire during scene load (before @onready) without touching null nodes.
func _refresh() -> void:
	if not is_node_ready():
		return
	_health_arc.min_value = 0.0
	_health_arc.max_value = HEALTH_SPLIT
	_health_bar.min_value = HEALTH_SPLIT
	_health_bar.max_value = 100.0
	_health_arc.value = clampf(health_value, 0.0, HEALTH_SPLIT)
	_health_bar.value = clampf(health_value, HEALTH_SPLIT, 100.0)
	_stamina.value = stamina_value
	_mana.value = mana_value

# EventBus handlers route through the exported properties so their setters
# refresh the view and the inspector stays in sync with the live value.
func set_health(value: float) -> void:
	health_value = value

func set_stamina(value: float) -> void:
	stamina_value = value

func set_mana(value: float) -> void:
	mana_value = value
