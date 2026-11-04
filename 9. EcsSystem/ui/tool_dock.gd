extends PanelContainer

## Module 9's tool dock: the Place, Compose and Outliner tabs. Leaving Place
## stops placing.

@onready var _tabs: TabBar = %Tabs
@onready var _pages: Array[Control] = [%PlacePanel, %Composer, %Outliner]

func _ready() -> void:
	_tabs.tab_changed.connect(_show_page)
	_show_page(_tabs.current_tab)

func _show_page(index: int) -> void:
	for i in _pages.size():
		_pages[i].visible = i == index
	if index != 0:
		EventBus.ecs_place_type_chosen.emit(&"")
