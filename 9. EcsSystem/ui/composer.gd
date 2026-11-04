extends VBoxContainer

## Module 9's Compose tab: a library of every blueprint, and an editor that
## builds one from components and saves it to user://blueprints/. Edits
## blueprint data only, never the world; main.gd adds a saved file to its
## catalog. Resource and array fields keep the values they were copied with.

const BLUEPRINT_DIR := "user://blueprints/"
const COMPONENT_DIR := "res://9. EcsSystem/components/"
## Where resource lists (skills, actions, goals) are picked from.
const DEFS_DIR := "res://9. EcsSystem/defs/"
## Added by EcsEntityManager to every entity, so never part of a blueprint.
const IMPLICIT := [&"EcsNameComponent", &"EcsPositionComponent"]

## Every blueprint main.gd can spawn, by id.
var _defs: Dictionary = {}
## The blueprint being built.
var _components: Array[EcsComponent] = []
## Class name -> script path, for components that can be added.
var _addable: Dictionary = {}
## Id waiting on a second press of Delete, or empty.
var _deleting: StringName = &""
## Class name -> every .tres under DEFS_DIR of that class, found on first use.
var _defs_of_class: Dictionary = {}

@onready var _library: ItemList = %Library
@onready var _open: Button = %OpenButton
@onready var _delete: Button = %DeleteButton
@onready var _editing: Label = %EditingLabel
@onready var _id: LineEdit = %IdField
@onready var _display: LineEdit = %NameField
@onready var _list: ItemList = %ComponentList
@onready var _add: OptionButton = %AddOption
@onready var _fields_title: Label = %FieldsTitle
@onready var _fields: VBoxContainer = %Fields
@onready var _status: Label = %Status

func _ready() -> void:
	_find_addable()
	EventBus.ecs_catalog_changed.connect(_on_catalog_changed)
	_library.item_selected.connect(func(_index: int) -> void: _refresh_library_buttons())
	_library.item_activated.connect(func(_index: int) -> void: _on_open_pressed())
	_open.pressed.connect(_on_open_pressed)
	_delete.pressed.connect(_on_delete_pressed)
	_list.item_selected.connect(func(_index: int) -> void: _show_fields())
	%AddButton.pressed.connect(_on_add_pressed)
	%RemoveButton.pressed.connect(_on_remove_pressed)
	%NewButton.pressed.connect(_on_new_pressed)
	%SaveButton.pressed.connect(_on_save_pressed)
	_on_new_pressed()

func _on_catalog_changed(defs: Array) -> void:
	_defs.clear()
	_library.clear()
	for def: EcsEntityDef in defs:
		_defs[def.id] = def
		var index := _library.add_item("%s   · %s" % [def.id, "yours" if _is_composed(def) else "built-in"])
		_library.set_item_metadata(index, String(def.id))
	_deleting = &""
	_refresh_library_buttons()

## Loads the picked blueprint into the editor. A built-in one is a copy to save
## under a new id; a composed one keeps its id, so saving updates it.
func _on_open_pressed() -> void:
	var def := _picked_def()
	if def == null:
		return
	_components.clear()
	for template in def.components:
		if template != null:
			_components.append(template.duplicate(true))
	if _is_composed(def):
		_id.text = String(def.id)
		_display.text = def.display_name
		_editing.text = "Editing %s" % def.id
		_say("Opened %s; saving updates it" % def.id)
	else:
		_id.text = ""
		_display.text = ""
		_editing.text = "New, copied from %s" % def.id
		_say("Copied %s; give it a new name" % def.id)
	_refresh_components()

## Deletes a composed blueprint on a second press.
func _on_delete_pressed() -> void:
	var def := _picked_def()
	if def == null or not _is_composed(def):
		return
	if _deleting != def.id:
		_deleting = def.id
		_delete.text = "Really delete?"
		return
	EventBus.ecs_blueprint_delete_requested.emit(def.id)
	_say("Deleted %s" % def.id)

func _on_new_pressed() -> void:
	_components.clear()
	_id.text = ""
	_display.text = ""
	_editing.text = "New blueprint"
	_refresh_components()
	_say("")

func _on_add_pressed() -> void:
	if _add.selected < 0:
		return
	var script := load(_addable[StringName(_add.get_item_metadata(_add.selected))]) as Script
	for held in _components:
		if held.get_script() == script:
			_say("It already has one", true)
			return
	_components.append(script.new())
	_refresh_components()
	_list.select(_components.size() - 1)
	_show_fields()

func _on_remove_pressed() -> void:
	var picked := _list.get_selected_items()
	if picked.is_empty():
		_say("Pick a component to remove", true)
		return
	_components.remove_at(picked[0])
	_refresh_components()

func _on_save_pressed() -> void:
	var id := _id.text.strip_edges().to_snake_case()
	if id.is_empty():
		# No id typed: take it from the name.
		id = _display.text.strip_edges().to_snake_case()
		_id.text = id
	if id.is_empty():
		_say("Give it a name or an id", true)
		return
	var existing: EcsEntityDef = _defs.get(StringName(id))
	if existing != null and not _is_composed(existing):
		_say("'%s' is a built-in type; pick another name" % id, true)
		return
	if _components.is_empty():
		_say("Add at least one component", true)
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
		_say("Could not save (%s)" % error_string(error), true)
		return
	_editing.text = "Editing %s" % id
	_say("%s %s; it's on the Place tab" % ["Updated" if existing != null else "Saved", id])
	EventBus.ecs_blueprint_saved.emit(path)

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
		_add.add_item(_short(String(name)))
		_add.set_item_metadata(_add.item_count - 1, String(name))

func _refresh_components() -> void:
	_list.clear()
	for held in _components:
		_list.add_item(_short(_class_of(held)))
	_show_fields()

func _refresh_library_buttons() -> void:
	var def := _picked_def()
	_open.disabled = def == null
	_delete.disabled = def == null or not _is_composed(def)
	if def == null or def.id != _deleting:
		_deleting = &""
		_delete.text = "Delete"

## One editor per exported field of the selected component.
func _show_fields() -> void:
	for child in _fields.get_children():
		_fields.remove_child(child)
		child.queue_free()
	var picked := _list.get_selected_items()
	if picked.is_empty():
		_fields_title.text = "Pick a component to edit its fields"
		return
	var component := _components[picked[0]]
	_fields_title.text = "%s fields" % _short(_class_of(component))
	for property in component.get_property_list():
		var usage := int(property["usage"])
		if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or not (usage & PROPERTY_USAGE_EDITOR):
			continue
		_field_row(property["name"], _editor_for(component, property))

func _editor_for(component: EcsComponent, property: Dictionary) -> Control:
	var field: StringName = property["name"]
	var value: Variant = component.get(field)
	var editor := EcsFieldEditor.build(property, value, func(new_value: Variant) -> void:
		component.set(field, new_value))
	if editor != null:
		return editor
	var element := _array_class(property)
	if element != "":
		return _resource_checklist(component, field, element)
	if int(property["type"]) == TYPE_OBJECT and String(property["hint_string"]) == "Texture2D":
		return _texture_picker(component, field, value)
	var label := Label.new()
	label.theme_type_variation = &"DockHint"
	label.text = _summary(value)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
		options.get_popup().set_item_icon_max_width(options.item_count - 1, 24)
		if texture == value:
			options.select(options.item_count - 1)
	options.item_selected.connect(func(index: int) -> void:
		component.set(field, null if index == 0 else textures[index - 1]))
	return options

## The class of a typed resource array, e.g. "EcsSkillDef", or "".
func _array_class(property: Dictionary) -> String:
	if int(property["type"]) != TYPE_ARRAY:
		return ""
	# An exported typed array says "24/17:EcsSkillDef"; a plain one "EcsSkillDef".
	var hint := String(property["hint_string"])
	match int(property["hint"]):
		PROPERTY_HINT_TYPE_STRING:
			return hint.get_slice(":", 1) if hint.contains(":") else ""
		PROPERTY_HINT_ARRAY_TYPE:
			return hint
	return ""

## One tick box per definition file of `element`; ticked ones are the list.
func _resource_checklist(component: EcsComponent, field: StringName, element: String) -> Control:
	var box := VBoxContainer.new()
	box.theme_type_variation = &"SimVBox"
	var held: Array = component.get(field)
	var choices := _defs_of(element)
	if choices.is_empty():
		var none := Label.new()
		none.theme_type_variation = &"DockHint"
		none.text = "no %s files under defs/" % element
		box.add_child(none)
	for choice: Resource in choices:
		var tick := CheckBox.new()
		tick.focus_mode = Control.FOCUS_NONE
		tick.theme_type_variation = &"DockCheck"
		tick.text = choice.resource_path.get_file().get_basename()
		tick.button_pressed = held.has(choice)
		tick.toggled.connect(func(on: bool) -> void:
			var list: Array = (component.get(field) as Array).duplicate()
			if on and not list.has(choice):
				list.append(choice)
			elif not on:
				list.erase(choice)
			component.set(field, list))
		box.add_child(tick)
	return box

## Every .tres under DEFS_DIR whose script is `element` or extends it, by file name.
func _defs_of(element: String) -> Array:
	if _defs_of_class.has(element):
		return _defs_of_class[element]
	var found: Array = []
	var folders := [DEFS_DIR]
	while not folders.is_empty():
		var folder: String = folders.pop_back()
		for sub in DirAccess.get_directories_at(folder):
			folders.append(folder + sub + "/")
		for file in DirAccess.get_files_at(folder):
			var path := folder + file.trim_suffix(".remap")
			if path.get_extension() != "tres":
				continue
			var resource := load(path)
			var script := resource.get_script() as Script if resource != null else null
			# Subclasses count: each skill is its own EcsSkillDef class.
			while script != null and String(script.get_global_name()) != element:
				script = script.get_base_script()
			if script != null:
				found.append(resource)
	found.sort_custom(func(a: Resource, b: Resource) -> bool: return a.resource_path < b.resource_path)
	_defs_of_class[element] = found
	return found

func _field_row(label_text: String, editor: Control) -> void:
	var row := HBoxContainer.new()
	row.theme_type_variation = &"SimHBox"
	var label := Label.new()
	label.theme_type_variation = &"DockHint"
	label.text = label_text
	label.custom_minimum_size = Vector2(100, 0)
	label.clip_text = true
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if editor is LineEdit:
		editor.theme_type_variation = &"DockField"
	elif editor is Button and not editor is CheckBox:
		editor.theme_type_variation = &"DockButton"
	elif editor is CheckBox:
		editor.theme_type_variation = &"DockCheck"
	row.add_child(label)
	row.add_child(editor)
	_fields.add_child(row)

func _say(text: String, is_error: bool = false) -> void:
	_status.text = text
	_status.theme_type_variation = &"StatusError" if is_error else &"DockHint"

func _picked_def() -> EcsEntityDef:
	var picked := _library.get_selected_items()
	if picked.is_empty():
		return null
	return _defs.get(StringName(_library.get_item_metadata(picked[0])))

func _is_composed(def: EcsEntityDef) -> bool:
	return def.resource_path.begins_with(BLUEPRINT_DIR)

func _class_of(component: EcsComponent) -> String:
	var script := component.get_script() as Script
	var name := script.get_global_name() if script != null else &""
	return String(name) if name != &"" else String(component.key())

## "EcsConsumableComponent" -> "Consumable".
func _short(class_name_text: String) -> String:
	return class_name_text.trim_prefix("Ecs").trim_suffix("Component")

func _summary(value: Variant) -> String:
	if value is Array:
		return "%d items (kept)" % (value as Array).size()
	if value is Resource:
		var path := (value as Resource).resource_path
		return path.get_file() if path != "" else "(inline, kept)"
	return str(value)
