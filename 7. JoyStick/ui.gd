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
@onready var hold_ring: HoldRing = %HoldRing
@onready var inventory: Button = %Inventory
@onready var inventory_panel: InventoryPanel = %InventoryPanel

# Which of the two right-hand modes is active. The Switch button flips it:
# combat mode shows the BasicAttack joystick + skill wheel, interact mode shows
# the Interact joystick + pickup/place/craft wheel.
var combat_mode := true

# Seconds the Switch button must be held before the mode flips. The hold ring
# fills over this time via _hold_tween; releasing early kills it so no switch.
const SWITCH_HOLD_TIME := 0.6
var _hold_tween: Tween

# Duration of the pop/fade when swapping mode groups; _mode_tween drives it and
# is killed on re-entry so rapid switches don't overlap.
const MODE_ANIM_TIME := 0.18
var _mode_tween: Tween

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
	# Tap the Inventory button to slide the inventory panel in/out.
	inventory.pressed.connect(inventory_panel.toggle)
	_apply_mode(false)

func _on_switch_held() -> void:
	# Fill the ring over the hold time; when it completes, commit the switch.
	_kill_hold_tween()
	hold_ring.progress = 0.0
	_hold_tween = create_tween()
	_hold_tween.tween_property(hold_ring, "progress", 1.0, SWITCH_HOLD_TIME)
	_hold_tween.tween_callback(_commit_switch)

func _on_switch_released() -> void:
	# Released before the ring filled → cancel the pending switch and drain it.
	if hold_ring.progress < 1.0:
		_kill_hold_tween()
		_retract_ring()

## Flips the mode once the hold ring completes, then empties the ring.
func _commit_switch() -> void:
	combat_mode = not combat_mode
	_apply_mode()
	_retract_ring()

## Quickly animates the ring back to empty.
func _retract_ring() -> void:
	_hold_tween = create_tween()
	_hold_tween.tween_property(hold_ring, "progress", 0.0, 0.12)

func _kill_hold_tween() -> void:
	if _hold_tween and _hold_tween.is_valid():
		_hold_tween.kill()

## Shows exactly one of the two right-hand mode groups. When animate is true the
## incoming group pops in (fade + scale) while the outgoing one fades/shrinks out.
func _apply_mode(animate := true) -> void:
	var showing: Control = basic_attack if combat_mode else interact
	var hiding: Control = interact if combat_mode else basic_attack
	if _mode_tween and _mode_tween.is_valid():
		_mode_tween.kill()
	if not animate:
		showing.visible = true
		showing.modulate.a = 1.0
		showing.scale = Vector2.ONE
		hiding.visible = false
		return
	# Scale from the group's center so it grows/shrinks in place.
	showing.pivot_offset = showing.size * 0.5
	hiding.pivot_offset = hiding.size * 0.5
	showing.visible = true
	showing.modulate.a = 0.0
	showing.scale = Vector2(0.7, 0.7)
	_mode_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT)
	_mode_tween.set_trans(Tween.TRANS_BACK)  # slight overshoot pop on the incoming group
	_mode_tween.tween_property(showing, "scale", Vector2.ONE, MODE_ANIM_TIME)
	_mode_tween.set_trans(Tween.TRANS_SINE)  # smooth fades / outgoing shrink
	_mode_tween.tween_property(showing, "modulate:a", 1.0, MODE_ANIM_TIME)
	_mode_tween.tween_property(hiding, "modulate:a", 0.0, MODE_ANIM_TIME)
	_mode_tween.tween_property(hiding, "scale", Vector2(0.85, 0.85), MODE_ANIM_TIME)
	# Once faded out, fully hide the outgoing group and reset it for next time.
	_mode_tween.chain().tween_callback(func() -> void:
		hiding.visible = false
		hiding.modulate.a = 1.0
		hiding.scale = Vector2.ONE)

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
