extends PanelContainer

## Module 9's world menu: maps and saves in one list. Open builds a fresh copy of
## a map or loads a save as it was; New empty world starts with nothing in it.

var _maps := PackedStringArray()
var _saves: Array = []

@onready var _list: ItemList = %WorldList
@onready var _open: Button = %OpenButton

func _ready() -> void:
	EventBus.ecs_start_menu_opened.connect(func(map_names: PackedStringArray) -> void:
		_maps = map_names
		_refresh()
		show())
	EventBus.ecs_saves_changed.connect(func(saves: Array) -> void:
		_saves = saves
		_refresh())
	_list.item_activated.connect(func(_index: int) -> void: _on_open_pressed())
	_open.pressed.connect(_on_open_pressed)
	%NewEmptyButton.pressed.connect(func() -> void:
		EventBus.ecs_new_world_requested.emit("")
		hide())
	%CloseButton.pressed.connect(hide)

## Maps, then saves newest first; the first row is picked so Open always has a target.
func _refresh() -> void:
	_list.clear()
	for map_name in _maps:
		_list.set_item_metadata(_list.add_item("%s   · map" % map_name), [&"map", map_name])
	for save in _saves:
		_list.set_item_metadata(_list.add_item("%s   · save" % save["name"]), [&"save", save["name"]])
	if _list.item_count > 0:
		_list.select(0)
	_open.disabled = _list.item_count == 0

func _on_open_pressed() -> void:
	var picked := _list.get_selected_items()
	if picked.is_empty():
		return
	var world: Array = _list.get_item_metadata(picked[0])
	if world[0] == &"map":
		EventBus.ecs_new_world_requested.emit(world[1])
	else:
		EventBus.ecs_load_requested.emit(world[1])
	hide()
