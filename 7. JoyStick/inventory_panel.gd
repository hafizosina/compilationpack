class_name InventoryPanel
extends PanelContainer

## Slide-in inventory viewer. Listens on EventBus for content changes and rebuilds
## its slot grid; open()/close()/toggle() animate it in from the right edge.

const PANEL_WIDTH := 480.0
const SLIDE_TIME := 0.25
const COLUMNS := 4

@onready var _grid: GridContainer = %Grid
@onready var _close_button: Button = %CloseButton

var _slot_scene := preload("res://7. JoyStick/inventory_slot.tscn")
var _open := false
var _slide_tween: Tween

func _ready() -> void:
	_grid.columns = COLUMNS
	_close_button.pressed.connect(close)
	EventBus.inventory_changed.connect(_rebuild)
	_apply_slide(PANEL_WIDTH)  # start docked off-screen to the right
	visible = false

func toggle() -> void:
	if _open:
		close()
	else:
		open()

func open() -> void:
	_open = true
	visible = true
	_run_slide(0.0)

func close() -> void:
	_open = false
	_run_slide(PANEL_WIDTH, true)

## Tweens the panel between docked (0) and off-screen (PANEL_WIDTH).
func _run_slide(target_x: float, hide_after := false) -> void:
	if _slide_tween and _slide_tween.is_valid():
		_slide_tween.kill()
	_slide_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_slide_tween.tween_method(_apply_slide, offset_right, target_x, SLIDE_TIME)
	if hide_after:
		_slide_tween.tween_callback(func() -> void: visible = false)

## x = 0 docks the panel at the right edge; x = PANEL_WIDTH hides it off-screen.
func _apply_slide(x: float) -> void:
	offset_left = -PANEL_WIDTH + x
	offset_right = x

## Rebuilds the slot grid from the inventory's slot array (reusing slot nodes).
func _rebuild(slots: Array) -> void:
	while _grid.get_child_count() < slots.size():
		_grid.add_child(_slot_scene.instantiate())
	while _grid.get_child_count() > slots.size():
		var extra := _grid.get_child(_grid.get_child_count() - 1)
		_grid.remove_child(extra)
		extra.queue_free()
	for i in slots.size():
		(_grid.get_child(i) as InventorySlot).set_stack(slots[i])
