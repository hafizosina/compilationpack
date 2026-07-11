extends CanvasLayer

# MOBA-style controls. The left VirtualJoystick drives movement through the
# ui_* actions; the attack/skill joysticks use dedicated aim_* actions (so
# dragging them never moves the player) and are read via signals.
@onready var skills: Array[VirtualJoystick] = [%Skill1, %Skill2, %Skill3, %Skill4]
# Interact-mode controls: the aim joysticks cast via released/tapped like skills,
# while Craft/Button1 are plain buttons that fire on press.
@onready var interact_sticks: Array[VirtualJoystick] = [%PickUpItem, %PlaceItem]
@onready var interact_buttons: Array[Button] = [%Craft, %Button1]
@onready var basic_attack: VirtualJoystick = %BasicAttack
@onready var interact: VirtualJoystick = %Interact
@onready var sprint: Button = %Sprint
@onready var switch: Button = %Switch

# Which of the two right-hand modes is active. The Switch button flips it:
# combat mode shows the BasicAttack joystick + skill wheel, interact mode shows
# the Interact joystick + pickup/place/craft wheel.
var combat_mode := true

# Seconds the Switch button must be held before the mode flips. Each press bumps
# _hold_token so an early release (or a new press) cancels the pending switch.
const SWITCH_HOLD_TIME := 1.0
var _hold_token := 0

func _ready() -> void:
	_bind(basic_attack, "Basic Attack")
	_bind(interact, "Interact")
	for i in skills.size():
		_bind(skills[i], "Skill %d" % (i + 1))
	for stick in interact_sticks:
		_bind(stick, String(stick.name))
	for button in interact_buttons:
		button.pressed.connect(_on_button_pressed.bind(String(button.name)))
	# Hold the Sprint button to drive the "sprint" input action; the player
	# component reads that action, so the UI stays decoupled from the player.
	sprint.button_down.connect(func() -> void: Input.action_press("sprint"))
	sprint.button_up.connect(func() -> void: Input.action_release("sprint"))
	# Hold Switch for SWITCH_HOLD_TIME to flip modes; releasing early cancels it.
	switch.button_down.connect(_on_switch_held)
	switch.button_up.connect(_on_switch_released)
	_apply_mode()

func _on_switch_held() -> void:
	_hold_token += 1
	var token := _hold_token
	# TODO: add visual feedback for the hold (e.g. radial fill / progress on the
	# Switch button) so the player can see the 1s switch charging.
	await get_tree().create_timer(SWITCH_HOLD_TIME).timeout
	# Only flip if this same hold is still active (not released or re-pressed).
	if token == _hold_token and switch.button_pressed:
		combat_mode = not combat_mode
		_apply_mode()

func _on_switch_released() -> void:
	# Invalidate any pending hold started by the matching button_down.
	_hold_token += 1

## Shows exactly one of the two right-hand mode groups.
func _apply_mode() -> void:
	basic_attack.visible = combat_mode
	interact.visible = not combat_mode

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

## Fires when a plain interact button (Craft, Button1) is pressed.
func _on_button_pressed(label: String) -> void:
	print("%s pressed" % label)
