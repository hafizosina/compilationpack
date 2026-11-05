class_name EcsControlHud
extends CanvasLayer

## Module 7's touch HUD, wired for the ECS: a stick let go or tapped is sent out as an ability
## (main.gd records it for EcsPlayerControlSystem), and each skill stick dims while cooling.
## The movement stick and Sprint drive InputMap actions, as in module 7.

## An ability stick was let go, aimed `aim` (zero = not aimed).
signal ability_released(ability: StringName, aim: Vector2)
## An ability stick was tapped without a drag.
signal ability_tapped(ability: StringName)

const SWITCH_HOLD_TIME := 0.6
const MODE_ANIM_TIME := 0.18
## How dim a skill stick is right after use.
const COOLING_ALPHA := 0.35

@onready var skills: Array[VirtualJoystick] = [%Skill1, %Skill2, %Skill3, %Skill4]
@onready var interact_sticks: Array[VirtualJoystick] = [%PickUpItem, %PlaceItem]
@onready var basic_attack: VirtualJoystick = %BasicAttack
@onready var interact: VirtualJoystick = %Interact
@onready var sprint: Button = %Sprint
@onready var switch: Button = %Switch
@onready var hold_ring: HoldRing = %HoldRing
@onready var inventory: Button = %Inventory
@onready var inventory_panel: InventoryPanel = %InventoryPanel

## Combat mode shows Basic Attack and the skill wheel; interact mode the interact wheel.
var combat_mode := true
var _hold_tween: Tween
var _mode_tween: Tween

func _ready() -> void:
	_bind(basic_attack, EcsPlayerInputSingleton.ATTACK)
	for i in skills.size():
		_bind(skills[i], EcsPlayerInputSingleton.SKILLS[i])
	_bind(interact, &"interact")
	for stick in interact_sticks:
		_bind(stick, StringName(String(stick.name).to_snake_case()))
	sprint.button_down.connect(func() -> void: Input.action_press("sprint"))
	sprint.button_up.connect(func() -> void: Input.action_release("sprint"))
	switch.button_down.connect(_on_switch_held)
	switch.button_up.connect(_on_switch_released)
	inventory.pressed.connect(inventory_panel.toggle)
	_apply_mode(false)

## Dims each skill stick by its slot's cooldown: 1 just used, 0 ready.
func show_cooldowns(ratios: Array[float]) -> void:
	for i in mini(ratios.size(), skills.size()):
		skills[i].modulate.a = lerpf(1.0, COOLING_ALPHA, ratios[i])

func _bind(joystick: VirtualJoystick, ability: StringName) -> void:
	joystick.released.connect(func(aim: Vector2) -> void: ability_released.emit(ability, aim))
	joystick.tapped.connect(func() -> void: ability_tapped.emit(ability))

func _on_switch_held() -> void:
	_kill_hold_tween()
	hold_ring.progress = 0.0
	_hold_tween = create_tween()
	_hold_tween.tween_property(hold_ring, "progress", 1.0, SWITCH_HOLD_TIME)
	_hold_tween.tween_callback(_commit_switch)

func _on_switch_released() -> void:
	if hold_ring.progress < 1.0:
		_kill_hold_tween()
		_retract_ring()

func _commit_switch() -> void:
	combat_mode = not combat_mode
	_apply_mode()
	_retract_ring()

func _retract_ring() -> void:
	_hold_tween = create_tween()
	_hold_tween.tween_property(hold_ring, "progress", 0.0, 0.12)

func _kill_hold_tween() -> void:
	if _hold_tween and _hold_tween.is_valid():
		_hold_tween.kill()

## Shows one of the two right-hand groups, popping the incoming one in when `animate`.
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
	showing.pivot_offset = showing.size * 0.5
	hiding.pivot_offset = hiding.size * 0.5
	showing.visible = true
	showing.modulate.a = 0.0
	showing.scale = Vector2(0.7, 0.7)
	_mode_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT)
	_mode_tween.set_trans(Tween.TRANS_BACK)
	_mode_tween.tween_property(showing, "scale", Vector2.ONE, MODE_ANIM_TIME)
	_mode_tween.set_trans(Tween.TRANS_SINE)
	_mode_tween.tween_property(showing, "modulate:a", 1.0, MODE_ANIM_TIME)
	_mode_tween.tween_property(hiding, "modulate:a", 0.0, MODE_ANIM_TIME)
	_mode_tween.tween_property(hiding, "scale", Vector2(0.85, 0.85), MODE_ANIM_TIME)
	_mode_tween.chain().tween_callback(func() -> void:
		hiding.visible = false
		hiding.modulate.a = 1.0
		hiding.scale = Vector2.ONE)
