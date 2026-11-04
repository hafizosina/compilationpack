class_name EcsBuildPanel
extends PanelContainer

## The build HUD: a grid of tool icons, the tool's name and hint, swatches of its types
## drawn from the real tiles, a brush size for the brushes, and view toggles. A dumb view:
## main.gd fills it with `setup()` and hears it through its signals.

## A tool was picked, with the id of its chosen type (0 when it has none).
signal tool_picked(tool: StringName, id: int)
signal brush_size_changed(size: int)
## A view was switched: &"roofs" or &"rooms".
signal view_toggled(view: StringName, on: bool)

const MAX_BRUSH: int = 8
const TOOL_SIZE := Vector2(52, 52)
const SWATCH_SIZE := Vector2(68, 68)

@onready var _tools: GridContainer = %Tools
@onready var _tool_name: Label = %ToolName
@onready var _hint: Label = %Hint
@onready var _types_title: Label = %TypesTitle
@onready var _types: GridContainer = %Types
@onready var _brush: HBoxContainer = %Brush
@onready var _brush_size_label: Label = %BrushSize
@onready var _roofs: Button = %Roofs
@onready var _rooms: Button = %Rooms

var _tool_group := ButtonGroup.new()
## tool -> spec from setup(), plus "button" and the chosen "id".
var _specs: Dictionary = {}
var _open_tool: StringName = &""
var _type_buttons: Dictionary = {}
var _brush_size: int = 1

func _ready() -> void:
	_roofs.toggled.connect(func(on: bool) -> void: view_toggled.emit(&"roofs", on))
	_rooms.toggled.connect(func(on: bool) -> void: view_toggled.emit(&"rooms", on))
	(%Smaller as Button).pressed.connect(func() -> void: _resize(-1))
	(%Bigger as Button).pressed.connect(func() -> void: _resize(1))

## Builds the tool grid. `tools`: [{tool, label, hint, keys, icon, sized, choices: [{id, label, icon}]}].
func setup(tools: Array) -> void:
	for spec: Dictionary in tools:
		var button := Button.new()
		button.theme_type_variation = &"DockButton"
		button.toggle_mode = true
		button.button_group = _tool_group
		button.icon = spec.get("icon")
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.expand_icon = true
		button.custom_minimum_size = TOOL_SIZE
		button.tooltip_text = "%s  (%s)" % [spec["label"], spec.get("keys", "")]
		button.pressed.connect(_open.bind(spec["tool"], true))
		_tools.add_child(button)
		var entry := spec.duplicate()
		entry["button"] = button
		var choices: Array = spec.get("choices", [])
		entry["id"] = int(choices[0]["id"]) if not choices.is_empty() else 0
		_specs[spec["tool"]] = entry

## Shows `tool` and its type `id` as picked, without asking for anything (a shortcut key did).
func select(tool: StringName, id: int = -1) -> void:
	if not _specs.has(tool):
		return
	if id >= 0:
		_specs[tool]["id"] = id
	# set_pressed_no_signal skips the ButtonGroup, so the others are released by hand.
	for other: StringName in _specs:
		(_specs[other]["button"] as Button).set_pressed_no_signal(other == tool)
	_open(tool, false)

func set_brush_size(size: int) -> void:
	_brush_size = size
	_brush_size_label.text = str(size)

func set_views(roofs: bool, rooms: bool) -> void:
	_roofs.set_pressed_no_signal(roofs)
	_rooms.set_pressed_no_signal(rooms)

## Fills the name, hint, swatches and brush row for `tool`.
func _open(tool: StringName, announce: bool) -> void:
	var spec: Dictionary = _specs[tool]
	_open_tool = tool
	_tool_name.text = spec["label"]
	_hint.text = spec.get("hint", "")
	for child in _types.get_children():
		child.queue_free()
	_type_buttons.clear()
	var choices: Array = spec.get("choices", [])
	_types_title.visible = not choices.is_empty()
	_types.visible = not choices.is_empty()
	var group := ButtonGroup.new()
	for choice: Dictionary in choices:
		var swatch := Button.new()
		swatch.theme_type_variation = &"DockButton"
		swatch.toggle_mode = true
		swatch.button_group = group
		swatch.icon = choice.get("icon")
		swatch.expand_icon = true
		swatch.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		swatch.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		swatch.text = choice["label"]
		swatch.custom_minimum_size = SWATCH_SIZE
		swatch.tooltip_text = choice["label"]
		swatch.set_pressed_no_signal(int(choice["id"]) == int(spec["id"]))
		swatch.pressed.connect(_choose.bind(tool, int(choice["id"])))
		_types.add_child(swatch)
		_type_buttons[int(choice["id"])] = swatch
	_brush.visible = spec.get("sized", false)
	if announce:
		tool_picked.emit(tool, spec["id"])

func _choose(tool: StringName, id: int) -> void:
	_specs[tool]["id"] = id
	tool_picked.emit(tool, id)

func _resize(step: int) -> void:
	set_brush_size(clampi(_brush_size + step, 1, MAX_BRUSH))
	brush_size_changed.emit(_brush_size)
