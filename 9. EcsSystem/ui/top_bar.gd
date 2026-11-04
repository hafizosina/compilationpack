extends PanelContainer

## Module 9's top bar: the world and save menus, pause, overlay, respawn, the
## dock toggles, and the entity count and fps.

## The World or Save / Load button was pressed; the HUD opens that menu.
signal world_pressed
signal saves_pressed
## A dock toggle changed.
signal tools_toggled(shown: bool)
signal inspector_toggled(shown: bool)

@onready var _pause: Button = %PauseButton
@onready var _overlay: Button = %OverlayButton
@onready var _paused_label: Label = %PausedLabel
@onready var _count: Label = %CountLabel
@onready var _fps: Label = %FpsLabel

func _ready() -> void:
	%WorldButton.pressed.connect(world_pressed.emit)
	%SavesButton.pressed.connect(saves_pressed.emit)
	%RespawnButton.pressed.connect(EventBus.ecs_respawn_requested.emit)
	%ToolsButton.toggled.connect(tools_toggled.emit)
	%InspectorButton.toggled.connect(inspector_toggled.emit)
	# The buttons only ask; their look follows what main.gd reports back.
	_pause.pressed.connect(EventBus.ecs_pause_requested.emit)
	_overlay.pressed.connect(EventBus.ecs_overlay_toggle_requested.emit)
	EventBus.ecs_pause_changed.connect(_on_pause_changed)
	EventBus.ecs_overlay_changed.connect(_overlay.set_pressed_no_signal)
	EventBus.ecs_world_census.connect(func(count: int) -> void:
		_count.text = "%d entities" % count)

func _process(_delta: float) -> void:
	_fps.text = "%d fps" % Engine.get_frames_per_second()

func _on_pause_changed(paused: bool) -> void:
	_pause.set_pressed_no_signal(paused)
	_pause.text = "Resume" if paused else "Pause"
	_paused_label.visible = paused
