extends CanvasLayer

## Module 9 HUD: a stats block top-right with save/load and the placing palette,
## the composer, a tabbed inspector bottom-left (its Edit tab changes every
## selected entity) and a centred start menu. Renders what arrives on EventBus
## and asks for edits over it; holds no reference to the world.

## Width reserved for the key column so values line up.
const KEY_WIDTH := 96.0
## Section key of the Edit tab; no component has it.
const EDIT_TAB := "_edit"

@onready var count_label: Label = %CountLabel
@onready var fps_label: Label = %FpsLabel
@onready var respawn_button: Button = %RespawnButton
@onready var paused_label: Label = %PausedLabel
@onready var saves_button: Button = %SavesButton
@onready var place_button: Button = %PlaceButton
@onready var compose_button: Button = %ComposeButton
@onready var saves_box: Control = %SavesBox
@onready var save_name: LineEdit = %SaveName
@onready var save_list: ItemList = %SaveList
@onready var palette_box: Control = %PaletteBox
@onready var placing_label: Label = %PlacingLabel
@onready var type_list: ItemList = %TypeList
@onready var composer: Control = %Composer
@onready var start_menu: Control = %StartMenu
@onready var world_list: ItemList = %WorldList
@onready var open_button: Button = %OpenButton
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
## Map names and save names, as the Worlds list shows them.
var _map_names := PackedStringArray()
var _save_names := PackedStringArray()
## Ids of every selected entity; edits go to all of them.
var _ids: Array = []
## "component/field" keys laid out on the Edit tab, in order.
var _edit_keys: Array[String] = []
## "component/field" -> its editor control.
var _editors: Dictionary = {}

func _ready() -> void:
	EventBus.ecs_world_census.connect(_on_census)
	EventBus.ecs_entity_inspected.connect(_on_entity_inspected)
	EventBus.ecs_pause_changed.connect(_on_pause_changed)
	EventBus.ecs_saves_changed.connect(_on_saves_changed)
	EventBus.ecs_catalog_changed.connect(_on_catalog_changed)
	EventBus.ecs_place_type_chosen.connect(_on_place_type_chosen)
	EventBus.ecs_start_menu_opened.connect(_on_start_menu_opened)
	%MenuButton.pressed.connect(func() -> void: start_menu.visible = not start_menu.visible)
	%CloseButton.pressed.connect(start_menu.hide)
	world_list.item_activated.connect(func(_index: int) -> void: _on_open_pressed())
	open_button.pressed.connect(_on_open_pressed)
	%NewEmptyButton.pressed.connect(_on_new_empty_pressed)
	saves_button.toggled.connect(func(on: bool) -> void: saves_box.visible = on)
	place_button.toggled.connect(_on_place_toggled)
	compose_button.toggled.connect(func(on: bool) -> void: composer.visible = on)
	composer.visibility_changed.connect(func() -> void:
		compose_button.set_pressed_no_signal(composer.visible))
	%SaveButton.pressed.connect(_on_save_pressed)
	save_name.text_submitted.connect(func(_text: String) -> void: _on_save_pressed())
	%LoadButton.pressed.connect(_on_load_pressed)
	save_list.item_activated.connect(func(_index: int) -> void: _on_load_pressed())
	save_list.item_selected.connect(func(index: int) -> void:
		save_name.text = save_list.get_item_text(index))
	type_list.item_selected.connect(func(index: int) -> void:
		EventBus.ecs_place_type_chosen.emit(StringName(type_list.get_item_text(index))))
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

func _on_pause_changed(paused: bool) -> void:
	paused_label.visible = paused

func _on_save_pressed() -> void:
	var wanted := save_name.text.strip_edges()
	if not wanted.is_empty():
		EventBus.ecs_save_requested.emit(wanted)
	save_name.release_focus()

func _on_load_pressed() -> void:
	var picked := save_list.get_selected_items()
	if not picked.is_empty():
		EventBus.ecs_load_requested.emit(save_list.get_item_text(picked[0]))

func _on_saves_changed(names: PackedStringArray) -> void:
	save_list.clear()
	for entry in names:
		save_list.add_item(entry)
	_save_names = names
	_refresh_worlds()

func _on_start_menu_opened(map_names: PackedStringArray) -> void:
	_map_names = map_names
	_refresh_worlds()
	start_menu.show()

## Maps then saves in one list, the first row picked so Open always has a target.
func _refresh_worlds() -> void:
	world_list.clear()
	for entry in _map_names:
		world_list.set_item_metadata(world_list.add_item("%s   (map)" % entry), [&"map", entry])
	for entry in _save_names:
		world_list.set_item_metadata(world_list.add_item("%s   (save)" % entry), [&"save", entry])
	if world_list.item_count > 0:
		world_list.select(0)
	open_button.disabled = world_list.item_count == 0

## A map builds a fresh copy of its layout; a save loads as it was saved.
func _on_open_pressed() -> void:
	var picked := world_list.get_selected_items()
	if picked.is_empty():
		return
	var world: Array = world_list.get_item_metadata(picked[0])
	if world[0] == &"map":
		EventBus.ecs_new_world_requested.emit(world[1])
	else:
		EventBus.ecs_load_requested.emit(world[1])
	start_menu.hide()

func _on_new_empty_pressed() -> void:
	EventBus.ecs_new_world_requested.emit("")
	start_menu.hide()

func _on_catalog_changed(defs: Array) -> void:
	type_list.clear()
	for def: EcsEntityDef in defs:
		type_list.add_item(String(def.id))

func _on_place_toggled(on: bool) -> void:
	palette_box.visible = on
	if not on:
		EventBus.ecs_place_type_chosen.emit(&"")

func _on_place_type_chosen(type_id: StringName) -> void:
	if type_id == &"":
		type_list.deselect_all()
		placing_label.text = "Pick a type, then click to place"
	else:
		placing_label.text = "Placing %s (right-click stops)" % type_id

func _on_census(count: int) -> void:
	count_label.text = "%d entities" % count

## Shows a snapshot; empty means nothing selected. Tabs rebuild only when the set
## of sections changes.
func _on_entity_inspected(details: Dictionary) -> void:
	if details.is_empty():
		_ids = []
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
	_ids = details.get("ids", [])
	name_label.text = "%s   (%s)" % [details.get("name", "—"), details.get("type", "—")]
	if _ids.size() > 1:
		name_label.text += "   +%d more selected" % (_ids.size() - 1)

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
	sections[EDIT_TAB] = {"label": "Edit", "fields": {}, "editable": details.get("editable", {})}
	return sections

## Builds rows once per field set, then only updates their text.
func _render_current() -> void:
	if not _has_valid_tab():
		_clear_rows()
		return

	var section: Dictionary = _sections[_tab_keys[tabs.current_tab]]
	if section.has("editable"):
		_render_edit(section["editable"])
		return
	var fields: Dictionary = section["fields"]
	var keys: Array[String] = []
	for field in fields:
		keys.append(String(field))

	if keys != _row_keys or not _edit_keys.is_empty():
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
	_edit_keys = []
	_editors = {}

## One editor per raw field, grouped by component. Built once per field set; after
## that only values refresh, so typing isn't interrupted. A change asks for an
## edit of every selected entity.
func _render_edit(editable: Dictionary) -> void:
	var keys: Array[String] = []
	for component in editable:
		for field in editable[component]["fields"]:
			keys.append("%s/%s" % [component, field])
	if keys != _edit_keys:
		_clear_rows()
		_edit_keys = keys
		for component in editable:
			var header := Label.new()
			header.theme_type_variation = &"SimTitle"
			header.text = str(editable[component]["label"])
			detail.add_child(header)
			var fields: Dictionary = editable[component]["fields"]
			for field in fields:
				var key := "%s/%s" % [component, field]
				var editor := EcsFieldEditor.build(fields[field], fields[field]["value"],
					_requester(StringName(component), StringName(field)))
				_editors[key] = editor
				_add_editor_row(String(field), editor)
		scroll.set_deferred("scroll_vertical", 0)
		return
	for component in editable:
		var fields: Dictionary = editable[component]["fields"]
		for field in fields:
			EcsFieldEditor.refresh(_editors["%s/%s" % [component, field]], fields[field]["value"])

func _requester(component: StringName, field: StringName) -> Callable:
	return func(value: Variant) -> void:
		if not _ids.is_empty():
			EventBus.ecs_entity_edit_requested.emit(_ids.duplicate(), component, field, value)

func _add_editor_row(key: String, editor: Control) -> void:
	var row := HBoxContainer.new()
	row.theme_type_variation = &"SimHBox"
	var key_label := Label.new()
	key_label.theme_type_variation = &"SimLabel"
	key_label.text = key
	key_label.custom_minimum_size = Vector2(KEY_WIDTH, 0.0)
	key_label.clip_text = true
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(key_label)
	row.add_child(editor)
	detail.add_child(row)

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
