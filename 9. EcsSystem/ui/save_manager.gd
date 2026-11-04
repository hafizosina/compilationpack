extends PanelContainer

## Module 9's save manager: saves listed newest first with their time. Saving
## over an existing name and deleting both ask first, inline.

@onready var _list: ItemList = %SaveList
@onready var _name: LineEdit = %SaveName
@onready var _load: Button = %LoadButton
@onready var _delete: Button = %DeleteButton
@onready var _confirm_row: Control = %ConfirmRow
@onready var _confirm_label: Label = %ConfirmLabel
@onready var _status: Label = %Status

var _names := PackedStringArray()
## Run on Yes; empty when nothing waits for confirmation.
var _pending: Callable = Callable()

func _ready() -> void:
	EventBus.ecs_saves_changed.connect(_on_saves_changed)
	_list.item_selected.connect(func(index: int) -> void:
		_name.text = _names[index]
		_cancel()
		_refresh_buttons())
	_list.item_activated.connect(func(_index: int) -> void: _on_load_pressed())
	_name.text_submitted.connect(func(_text: String) -> void: _on_save_pressed())
	%SaveButton.pressed.connect(_on_save_pressed)
	_load.pressed.connect(_on_load_pressed)
	_delete.pressed.connect(_on_delete_pressed)
	%YesButton.pressed.connect(func() -> void:
		var action := _pending
		_cancel()
		action.call())
	%NoButton.pressed.connect(_cancel)
	%CloseButton.pressed.connect(hide)
	visibility_changed.connect(func() -> void:
		_cancel()
		_status.text = "")
	_refresh_buttons()

func _on_saves_changed(saves: Array) -> void:
	_list.clear()
	_names = PackedStringArray()
	for save in saves:
		_names.append(save["name"])
		_list.add_item("%s   ·  %s" % [save["name"], _when(int(save["time"]))])
	_refresh_buttons()

func _on_save_pressed() -> void:
	var wanted := _name.text.strip_edges()
	if wanted.is_empty():
		_status.text = "Type a name to save under"
		return
	_name.release_focus()
	if _names.has(wanted):
		_ask("Overwrite '%s'?" % wanted, _save.bind(wanted))
	else:
		_save(wanted)

func _save(save_name: String) -> void:
	EventBus.ecs_save_requested.emit(save_name)
	_status.text = "Saved '%s'" % save_name

func _on_load_pressed() -> void:
	var picked := _picked()
	if picked.is_empty():
		return
	EventBus.ecs_load_requested.emit(picked)
	hide()

func _on_delete_pressed() -> void:
	var picked := _picked()
	if picked.is_empty():
		return
	_ask("Delete '%s'?" % picked, func() -> void:
		EventBus.ecs_save_delete_requested.emit(picked)
		_status.text = "Deleted '%s'" % picked)

func _ask(question: String, action: Callable) -> void:
	_pending = action
	_confirm_label.text = question
	_confirm_row.show()

func _cancel() -> void:
	_pending = Callable()
	_confirm_row.hide()

func _picked() -> String:
	var picked := _list.get_selected_items()
	return _names[picked[0]] if not picked.is_empty() else ""

func _refresh_buttons() -> void:
	var none := _list.get_selected_items().is_empty()
	_load.disabled = none
	_delete.disabled = none

## Local date and time of a Unix timestamp, as "2026-11-04 14:02".
func _when(unix: int) -> String:
	var bias: int = Time.get_time_zone_from_system().get("bias", 0)
	var at := Time.get_datetime_dict_from_unix_time(unix + bias * 60)
	return "%04d-%02d-%02d %02d:%02d" % [at["year"], at["month"], at["day"], at["hour"], at["minute"]]
