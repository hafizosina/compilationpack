extends CanvasLayer

## Module 9's HUD: the top bar, the tool dock on the left, the inspector on the
## right, and the world and save menus. Each panel is its own scene and talks to
## the game only over EventBus; this only lays them out and opens the menus.

@onready var _tool_dock: Control = %ToolDock
@onready var _inspector: Control = %Inspector
@onready var _world_menu: Control = %WorldMenu
@onready var _save_manager: Control = %SaveManager

func _ready() -> void:
	var top_bar := %TopBar
	top_bar.world_pressed.connect(func() -> void: _open(_world_menu))
	top_bar.saves_pressed.connect(func() -> void: _open(_save_manager))
	top_bar.tools_toggled.connect(_tool_dock.set_visible)
	top_bar.inspector_toggled.connect(_inspector.set_visible)

## Shows one menu, or hides it if it is already open.
func _open(menu: Control) -> void:
	var opening := not menu.visible
	_world_menu.hide()
	_save_manager.hide()
	menu.visible = opening

## A wheel over any HUD control stops here, before the camera zooms with it.
## Runs ahead of the camera's because this node comes later in the scene.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index in [
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
			MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]):
		return
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered != null and is_ancestor_of(hovered):
		get_viewport().set_input_as_handled()
