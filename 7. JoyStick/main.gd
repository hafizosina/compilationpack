extends Node2D

# MOBA-style right-hand controls. The left VirtualJoystick drives movement
# through the ui_* actions; these attack/skill joysticks use dedicated aim_*
# actions (so dragging them never moves the player) and are read via signals.

@onready var basic_attack: VirtualJoystick = $UI/BasicAttack
@onready var skills: Array[VirtualJoystick] = [
	$UI/Skill1,
	$UI/Skill2,
	$UI/Skill3,
]

@onready var status_bar = $UI/StatusBar  # StatusBar (status_bar.gd); dynamic so set_* resolve at runtime
@onready var health_slider: HSlider = $UI/Temp/Sliders/HealthRow/HealthSlider
@onready var stamina_slider: HSlider = $UI/Temp/Sliders/StaminaRow/StaminaSlider
@onready var mana_slider: HSlider = $UI/Temp/Sliders/ManaRow/ManaSlider

func _ready() -> void:
	_bind(basic_attack, "Basic Attack")
	for i in skills.size():
		_bind(skills[i], "Skill %d" % (i + 1))

	# Debug harness: the Temp sliders drive the three status bars live.
	health_slider.value_changed.connect(status_bar.set_health)
	stamina_slider.value_changed.connect(status_bar.set_stamina)
	mana_slider.value_changed.connect(status_bar.set_mana)
	status_bar.set_health(health_slider.value)
	status_bar.set_stamina(stamina_slider.value)
	status_bar.set_mana(mana_slider.value)

func _bind(joystick: VirtualJoystick, ability: String) -> void:
	joystick.released.connect(_on_released.bind(ability))
	joystick.tapped.connect(_on_tapped.bind(ability))

## Fires when the finger lifts. input_vector is the aim direction (zero = no aim).
func _on_released(input_vector: Vector2, ability: String) -> void:
	if input_vector == Vector2.ZERO:
		return
	print("%s cast toward %s" % [ability, input_vector.normalized()])

## Fires on a quick tap with no drag — use for instant/self-cast abilities.
func _on_tapped(ability: String) -> void:
	print("%s quick cast" % ability)
