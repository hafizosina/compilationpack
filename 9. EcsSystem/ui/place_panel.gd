extends VBoxContainer

## Module 9's Place tab: every blueprint with its sprite. Picking one starts
## placing it on left-click; Stop, right-click or Escape ends that.

const ICON_SIZE := Vector2i(28, 28)

## Stands in for a blueprint with no sprite texture, so names stay aligned.
var _blank: Texture2D

@onready var _list: ItemList = %TypeList
@onready var _placing: Label = %PlacingLabel
@onready var _stop: Button = %StopButton

func _ready() -> void:
	EventBus.ecs_catalog_changed.connect(_on_catalog_changed)
	EventBus.ecs_place_type_chosen.connect(_on_place_type_chosen)
	_list.item_selected.connect(func(index: int) -> void:
		EventBus.ecs_place_type_chosen.emit(StringName(_list.get_item_metadata(index))))
	_stop.pressed.connect(func() -> void: EventBus.ecs_place_type_chosen.emit(&""))
	_list.fixed_icon_size = ICON_SIZE
	var image := Image.create(ICON_SIZE.x, ICON_SIZE.y, false, Image.FORMAT_RGBA8)
	_blank = ImageTexture.create_from_image(image)
	_on_place_type_chosen(&"")

func _on_catalog_changed(defs: Array) -> void:
	_list.clear()
	for def: EcsEntityDef in defs:
		var sprite := def.template(&"sprite") as EcsSpriteComponent
		var label := def.display_name if not def.display_name.is_empty() else String(def.id)
		if label.to_snake_case() != String(def.id):
			label += "   (%s)" % def.id
		var icon := sprite.texture if sprite != null and sprite.texture != null else _blank
		var index := _list.add_item(label, icon)
		_list.set_item_metadata(index, String(def.id))
		if sprite != null:
			_list.set_item_icon_modulate(index, sprite.tint)

func _on_place_type_chosen(type_id: StringName) -> void:
	_stop.disabled = type_id == &""
	if type_id == &"":
		_list.deselect_all()
		_placing.text = "Not placing"
		return
	_placing.text = "Placing %s" % type_id
