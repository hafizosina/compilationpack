extends CanvasLayer

## Module 9 HUD: a stats block top-right and a tabbed inspector bottom-left.
## Renders what arrives on EventBus; holds no reference to the world.

## Width reserved for the key column so values line up.
const KEY_WIDTH := 96.0

@onready var count_label: Label = %CountLabel
@onready var fps_label: Label = %FpsLabel
@onready var respawn_button: Button = %RespawnButton
@onready var name_label: Label = %NameLabel
@onready var tabs: TabBar = %Tabs
@onready var scroll: ScrollContainer = %Scroll
@onready var detail: VBoxContainer = %Detail
@onready var inspector_panel: PanelContainer = $Root/InspectorHolder/InspectorRow/InspectorPanel

## Section keys currently on the tab bar, in tab order.
var _tab_keys: Array[String] = []
## key -> { "label": String, "fields": Dictionary }
var _sections: Dictionary = {}
## Field keys currently laid out in the detail list, in order.
var _row_keys: Array[String] = []
## Field key -> the Label showing its value.
var _row_values: Dictionary = {}

func _ready() -> void:
	EventBus.ecs_world_census.connect(_on_census)
	EventBus.ecs_entity_inspected.connect(_on_entity_inspected)
	respawn_button.pressed.connect(_on_respawn_pressed)
	tabs.tab_changed.connect(_on_tab_changed)
	inspector_panel.gui_input.connect(_on_inspector_input)
	_on_entity_inspected({})

## Consume wheel events over the panel so the camera doesn't zoom.
func _on_inspector_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index in [
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
			MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		inspector_panel.accept_event()

func _process(_delta: float) -> void:
	fps_label.text = "%d fps" % Engine.get_frames_per_second()

func _on_census(count: int) -> void:
	count_label.text = "%d entities" % count

## Shows a snapshot; empty means nothing selected. Tabs rebuild only when the set
## of sections changes.
func _on_entity_inspected(details: Dictionary) -> void:
	if details.is_empty():
		_tab_keys = []
		_sections = {}
		tabs.clear_tabs()
		tabs.visible = false
		name_label.text = "Click an entity to inspect it"
		_clear_rows()
		return

	_sections = _sections_from(details)
	var keys: Array[String] = []
	for key in _sections:
		keys.append(key)
	name_label.text = "%s   (%s)" % [details.get("name", "—"), details.get("type", "—")]

	if keys != _tab_keys:
		# Keep the current tab if it still exists.
		var wanted := _tab_keys[tabs.current_tab] if _has_valid_tab() else ""
		_tab_keys = keys
		tabs.clear_tabs()
		for key in keys:
			tabs.add_tab(str(_sections[key]["label"]))
		tabs.visible = true
		tabs.current_tab = maxi(keys.find(wanted), 0)
	_render_current()

func _on_tab_changed(_tab: int) -> void:
	_render_current()

func _on_respawn_pressed() -> void:
	EventBus.ecs_respawn_requested.emit()

## The entity section, then one section per component, as sent.
func _sections_from(details: Dictionary) -> Dictionary:
	var sections := {}
	sections["entity"] = {"label": "Entity", "fields": details.get("fields", {})}

	var components: Dictionary = details.get("components", {})
	for key in components:
		var section: Dictionary = components[key]
		sections[String(key)] = {
			"label": str(section.get("label", key)),
			"fields": section.get("fields", {}),
		}
	return sections

## Builds rows once per field set, then only updates their text.
func _render_current() -> void:
	if not _has_valid_tab():
		_clear_rows()
		return

	var fields: Dictionary = _sections[_tab_keys[tabs.current_tab]]["fields"]
	var keys: Array[String] = []
	for field in fields:
		keys.append(String(field))

	if keys != _row_keys:
		_clear_rows()
		_row_keys = keys
		for field in keys:
			_row_values[field] = _add_row(field)
		# New field set: scroll back to the top.
		scroll.set_deferred("scroll_vertical", 0)

	for field in keys:
		var value_label: Label = _row_values[field]
		value_label.text = str(fields[field])

func _has_valid_tab() -> bool:
	return tabs.current_tab >= 0 and tabs.current_tab < _tab_keys.size()

## Detaches before freeing so old rows don't show for a frame.
func _clear_rows() -> void:
	for child in detail.get_children():
		detail.remove_child(child)
		child.queue_free()
	_row_keys = []
	_row_values = {}

## Adds one key/value row and hands back the Label its value lives in.
func _add_row(key: String) -> Label:
	var row := HBoxContainer.new()
	row.theme_type_variation = &"SimHBox"
	var key_label := Label.new()
	key_label.theme_type_variation = &"SimLabel"
	key_label.text = key
	key_label.custom_minimum_size = Vector2(KEY_WIDTH, 0.0)
	key_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	var value_label := Label.new()
	value_label.theme_type_variation = &"SimLabel"
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Long values wrap.
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(key_label)
	row.add_child(value_label)
	detail.add_child(row)
	return value_label
