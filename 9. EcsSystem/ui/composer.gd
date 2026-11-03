extends PanelContainer

## Builds a blueprint from components and saves it to user://blueprints/.
## Edits blueprint data only, never the world; main.gd adds the saved file to
## its catalog. Resource and array fields keep the start type's values.

const BLUEPRINT_DIR := "user://blueprints/"
const COMPONENT_DIR := "res://9. EcsSystem/components/"
## Added by EcsEntityManager to every entity, so never part of a blueprint.
const IMPLICIT := [&"EcsNameComponent", &"EcsPositionComponent"]

## Every blueprint main.gd can spawn, by id.
var _defs: Dictionary = {}
## The blueprint being built.
var _components: Array[EcsComponent] = []
## Class name -> script path, for components that can be added.
var _addable: Dictionary = {}

var _start: OptionButton
var _id: LineEdit
var _display: LineEdit
var _list: ItemList
var _add: OptionButton
var _fields: VBoxContainer
var _status: Label

func _ready() -> void:
	_build_ui()
	_find_addable()
	EventBus.ecs_catalog_changed.connect(_on_catalog_changed)
	gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			accept_event())

func _on_catalog_changed(defs: Array) -> void:
	_defs.clear()
	for def: EcsEntityDef in defs:
		_defs[def.id] = def
	var chosen := _start.get_item_text(_start.selected) if _start.selected >= 0 else "(empty)"
	_start.clear()
	_start.add_item("(empty)")
	for id: StringName in _defs:
		_start.add_item(String(id))
		if String(id) == chosen:
			_start.select(_start.item_count - 1)

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.theme_type_variation = &"SimVBox"
	root.custom_minimum_size = Vector2(520, 0)
	add_child(root)

	var title := Label.new()
	title.theme_type_variation = &"SimTitle"
	title.text = "Compose an entity"
	root.add_child(title)

	var start_row := _row(root, "Start from")
	_start = OptionButton.new()
	_start.focus_mode = Control.FOCUS_NONE
	_start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_row.add_child(_start)
	var load_button := _button(start_row, "Copy")
	load_button.pressed.connect(_on_copy_pressed)

	_id = LineEdit.new()
	_id.placeholder_text = "id, e.g. hare"
	_id.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row(root, "Id").add_child(_id)
	_display = LineEdit.new()
	_display.placeholder_text = "display name"
	_display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row(root, "Name").add_child(_display)

	var split := HBoxContainer.new()
	split.theme_type_variation = &"SimHBox"
	root.add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(200, 0)
	split.add_child(left)
	_list = ItemList.new()
	_list.focus_mode = Control.FOCUS_NONE
	_list.custom_minimum_size = Vector2(200, 260)
	_list.item_selected.connect(func(_index: int) -> void: _show_fields())
	left.add_child(_list)
	var add_row := HBoxContainer.new()
	left.add_child(add_row)
	_add = OptionButton.new()
	_add.focus_mode = Control.FOCUS_NONE
	_add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add.fit_to_longest_item = false
	add_row.add_child(_add)
	_button(add_row, "Add").pressed.connect(_on_add_pressed)
	_button(left, "Remove selected").pressed.connect(_on_remove_pressed)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 300)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(scroll)
	_fields = VBoxContainer.new()
	_fields.theme_type_variation = &"SimVBox"
	_fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_fields)

	var bottom := HBoxContainer.new()
	root.add_child(bottom)
	_button(bottom, "Save blueprint").pressed.connect(_on_save_pressed)
	_button(bottom, "Close").pressed.connect(hide)
	_status = Label.new()
	_status.theme_type_variation = &"SimLabel"
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(_status)

## Components that extend EcsComponent and live in components/. Read from the
## class registry, which an export keeps, rather than by listing res://.
func _find_addable() -> void:
	var bases := {}
	var paths := {}
	for entry in ProjectSettings.get_global_class_list():
		bases[entry["class"]] = entry["base"]
		paths[entry["class"]] = entry["path"]
	for name: StringName in paths:
		if name in IMPLICIT or not String(paths[name]).begins_with(COMPONENT_DIR):
			continue
		var base: StringName = bases.get(name, &"")
		while base != &"" and base != &"EcsComponent":
			base = bases.get(base, &"")
		if base == &"EcsComponent":
			_addable[name] = paths[name]
	var names := _addable.keys()
	names.sort()
	_add.clear()
	for name in names:
		_add.add_item(String(name))

func _on_copy_pressed() -> void:
	_components.clear()
	var picked := _start.get_item_text(_start.selected) if _start.selected >= 0 else ""
	var source: EcsEntityDef = _defs.get(StringName(picked))
	if source != null:
		for template in source.components:
			if template != null:
				_components.append(template.duplicate(true))
		_display.text = source.display_name
	_refresh_list()
	_status.text = "Copied %s" % picked

func _on_add_pressed() -> void:
	if _add.selected < 0:
		return
	var script := load(_addable[StringName(_add.get_item_text(_add.selected))]) as Script
	for held in _components:
		if held.get_script() == script:
			_status.text = "It already has one"
			return
	_components.append(script.new())
	_refresh_list()
	_list.select(_components.size() - 1)
	_show_fields()

func _on_remove_pressed() -> void:
	var picked := _list.get_selected_items()
	if picked.is_empty():
		return
	_components.remove_at(picked[0])
	_refresh_list()

func _on_save_pressed() -> void:
	var id := _id.text.strip_edges().to_snake_case()
	if id.is_empty():
		_status.text = "Give it an id"
		return
	var existing: EcsEntityDef = _defs.get(StringName(id))
	if existing != null and existing.resource_path.begins_with("res://"):
		_status.text = "'%s' is a built-in type; pick another id" % id
		return
	if _components.is_empty():
		_status.text = "Add at least one component"
		return
	var def := EcsEntityDef.new()
	def.id = StringName(id)
	def.display_name = _display.text.strip_edges() if not _display.text.strip_edges().is_empty() else id
	for held in _components:
		def.components.append(held.duplicate(true))
	DirAccess.make_dir_recursive_absolute(BLUEPRINT_DIR)
	var path := BLUEPRINT_DIR + id + ".tres"
	var error := ResourceSaver.save(def, path)
	if error != OK:
		_status.text = "Could not save (%s)" % error_string(error)
		return
	_status.text = "Saved %s" % path
	EventBus.ecs_blueprint_saved.emit(path)

func _refresh_list() -> void:
	_list.clear()
	for held in _components:
		_list.add_item(_class_of(held))
	_show_fields()

func _class_of(component: EcsComponent) -> String:
	var script := component.get_script() as Script
	var name := script.get_global_name() if script != null else &""
	return String(name) if name != &"" else String(component.key())

## One editor per exported field of the selected component.
func _show_fields() -> void:
	for child in _fields.get_children():
		_fields.remove_child(child)
		child.queue_free()
	var picked := _list.get_selected_items()
	if picked.is_empty():
		return
	var component := _components[picked[0]]
	for property in component.get_property_list():
		var usage := int(property["usage"])
		if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or not (usage & PROPERTY_USAGE_EDITOR):
			continue
		var row := _row(_fields, property["name"])
		row.add_child(_editor_for(component, property))

func _editor_for(component: EcsComponent, property: Dictionary) -> Control:
	var field: StringName = property["name"]
	var value: Variant = component.get(field)
	var editor := EcsFieldEditor.build(property, value, func(new_value: Variant) -> void:
		component.set(field, new_value))
	if editor != null:
		return editor
	if int(property["type"]) == TYPE_OBJECT and String(property["hint_string"]) == "Texture2D":
		return _texture_picker(component, field, value)
	var label := Label.new()
	label.theme_type_variation = &"SimLabel"
	label.text = _summary(value)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

## Textures any known blueprint already uses.
func _texture_picker(component: EcsComponent, field: StringName, value: Variant) -> Control:
	var textures: Array[Texture2D] = []
	for def: EcsEntityDef in _defs.values():
		for template in def.components:
			if template == null:
				continue
			for property in template.get_property_list():
				var held: Variant = template.get(property["name"])
				if held is Texture2D and not textures.has(held):
					textures.append(held)
	var options := OptionButton.new()
	options.focus_mode = Control.FOCUS_NONE
	options.add_item("(none)")
	for texture in textures:
		options.add_icon_item(texture, texture.resource_path.get_file().get_basename())
		options.set_item_icon_max_width(options.item_count - 1, 24)
		if texture == value:
			options.select(options.item_count - 1)
	options.item_selected.connect(func(index: int) -> void:
		component.set(field, null if index == 0 else textures[index - 1]))
	return options

func _summary(value: Variant) -> String:
	if value is Array:
		return "%d items (kept)" % (value as Array).size()
	if value is Resource:
		var path := (value as Resource).resource_path
		return path.get_file() if path != "" else "(inline, kept)"
	return str(value)

func _row(parent: Control, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.theme_type_variation = &"SimHBox"
	var label := Label.new()
	label.theme_type_variation = &"SimLabel"
	label.text = label_text
	label.custom_minimum_size = Vector2(110, 0)
	row.add_child(label)
	parent.add_child(row)
	return row

func _button(parent: Control, text: String) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.text = text
	parent.add_child(button)
	return button
