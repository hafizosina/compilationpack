extends CanvasLayer

# MOBA-style controls. The left VirtualJoystick drives movement through the
# ui_* actions; the attack/skill joysticks use dedicated aim_* actions (so
# dragging them never moves the player) and are read via signals.
@onready var basic_attack: VirtualJoystick = $MarginContainer/HBoxContainer/RightGroup/BasicAttack
@onready var skills: Array[VirtualJoystick] = [%Skill1, %Skill2, %Skill3]
@onready var sprint: TextureButton = $MarginContainer/HBoxContainer/RightGroup/Sprint

func _ready() -> void:
	_bind(basic_attack, "Basic Attack")
	for i in skills.size():
		_bind(skills[i], "Skill %d" % (i + 1))
	# Hold the Sprint button to drive the "sprint" input action; the player
	# component reads that action, so the UI stays decoupled from the player.
	sprint.button_down.connect(func() -> void: Input.action_press("sprint"))
	sprint.button_up.connect(func() -> void: Input.action_release("sprint"))

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
