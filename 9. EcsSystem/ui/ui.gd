extends CanvasLayer

## Module 9's read-outs, laid out like module 8's: a stats block top-right, a
## tabbed inspector bottom-left, and — new here — the system pipeline
## bottom-right. Each is anchored to its own corner rather than sharing a
## column, so none can push or cover another however tall the inspector grows.
##
## The inspector's tabs are not hardcoded and, unlike module 8's, no component
## had to describe itself to earn one. EcsInspectSystem reflects over whatever
## components the selected entity carries; this panel just renders the sections
## it is handed. Adding a component kind adds its tab with no change here and
## none in the component.
##
## Its height is fixed and the fields scroll, so the panel never changes size
## under the cursor as you switch tabs or entities.
##
## The panel holds no reference to an entity, to the world, or to the scheduler.
## Counts, snapshots and the pipeline all arrive on the EventBus already
## formatted, and the respawn button asks for a rebuild the same way.

## Width reserved for the key column so values line up.
const KEY_WIDTH := 96.0

@onready var count_label: Label = %CountLabel
@onready var fps_label: Label = %FpsLabel
@onready var respawn_button: Button = %RespawnButton
@onready var pipeline_label: Label = %PipelineLabel
@onready var name_label: Label = %NameLabel
@onready var tabs: TabBar = %Tabs
@onready var scroll: ScrollContainer = %Scroll
@onready var detail: VBoxContainer = %Detail

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
	EventBus.ecs_pipeline_changed.connect(_on_pipeline_changed)
	respawn_button.pressed.connect(_on_respawn_pressed)
	tabs.tab_changed.connect(_on_tab_changed)
	_on_entity_inspected({})

func _process(_delta: float) -> void:
	fps_label.text = "%d fps" % Engine.get_frames_per_second()

func _on_census(count: int) -> void:
	count_label.text = "%d entities" % count

func _on_pipeline_changed(text: String) -> void:
	pipeline_label.text = text

## Rebuilds the inspector from a snapshot; an empty dictionary means nothing is
## selected. Snapshots arrive several times a second, so the tab strip is only
## rebuilt when the set of sections actually changes — otherwise the tab you are
## reading would reset under you.
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
		# Stay on the same section when it survives the rebuild, so clicking
		# between entities doesn't keep throwing you back to the first tab.
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

## One section for the entity's own facts, then one per component exactly as the
## inspect system reported it — heading, fields and field order all come from
## the component's own declarations, so nothing here names a component type.
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

## Lays the rows out once per field set, then only rewrites their text. A full
## rebuild several times a second would churn nodes and reset the scroll
## position out from under whoever is reading.
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
		# A different field set means a different section — start from the top.
		scroll.set_deferred("scroll_vertical", 0)

	for field in keys:
		var value_label: Label = _row_values[field]
		value_label.text = str(fields[field])

func _has_valid_tab() -> bool:
	return tabs.current_tab >= 0 and tabs.current_tab < _tab_keys.size()

## Detaches before freeing: queue_free() alone leaves the old rows parented for
## the rest of the frame, so the panel would briefly show two sections at once.
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
	# Long values (the component list) wrap instead of widening the panel.
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(key_label)
	row.add_child(value_label)
	detail.add_child(row)
	return value_label
