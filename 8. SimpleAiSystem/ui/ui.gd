extends CanvasLayer

## Two read-outs for the running world: population counts top-right, and a
## bottom-left inspector for whichever entity is currently selected. They are
## anchored to opposite corners rather than sharing a column, so neither can
## push or cover the other however tall the inspector grows.
##
## The inspector is tabbed, and the tabs are not hardcoded: the entity gets one,
## then every component that describes itself contributes another, titled and
## ordered by that component. Adding a component kind adds its tab with no
## change here.
##
## The panel holds no reference to an entity or to the factory. Counts and
## inspector snapshots both arrive on the EventBus already formatted, and the
## respawn button asks for a rebuild the same way.

## Width reserved for the key column so values line up.
const KEY_WIDTH := 104.0

@onready var counts_label: Label = %CountsLabel
@onready var fps_label: Label = %FpsLabel
@onready var respawn_button: Button = %RespawnButton
@onready var name_label: Label = %NameLabel
@onready var tabs: TabBar = %Tabs
@onready var detail: VBoxContainer = %Detail

## Section keys currently on the tab bar, in tab order.
var _tab_keys: Array[String] = []
## key -> { "label": String, "fields": Dictionary }
var _sections: Dictionary = {}

func _ready() -> void:
	EventBus.sim_world_spawned.connect(_on_world_spawned)
	EventBus.sim_entity_inspected.connect(_on_entity_inspected)
	respawn_button.pressed.connect(_on_respawn_pressed)
	tabs.tab_changed.connect(_on_tab_changed)
	_on_entity_inspected({})

func _process(_delta: float) -> void:
	fps_label.text = "%d fps" % Engine.get_frames_per_second()

func _on_world_spawned(census: Dictionary) -> void:
	var lines: Array[String] = []
	var total := 0
	for id in census:
		var count: int = census[id]
		total += count
		lines.append("%s   %d" % [id, count])
	lines.append("total   %d" % total)
	counts_label.text = "\n".join(lines)

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
		_clear(detail)
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
	EventBus.sim_respawn_requested.emit()

## One section for the entity's own facts, then one per component exactly as it
## described itself — heading, fields and field order all come from it.
func _sections_from(details: Dictionary) -> Dictionary:
	var sections := {}
	var own := {}
	for key in ["type", "position", "home", "from home", "slots"]:
		own[key] = str(details.get(key, "—"))
	sections["entity"] = {"label": "Entity", "fields": own}

	var components: Dictionary = details.get("components", {})
	for slot in components:
		var section: Dictionary = components[slot]
		sections[String(slot)] = {
			"label": str(section.get("label", slot)),
			"fields": section.get("fields", {}),
		}
	return sections

func _render_current() -> void:
	_clear(detail)
	if not _has_valid_tab():
		return
	var fields: Dictionary = _sections[_tab_keys[tabs.current_tab]]["fields"]
	for field in fields:
		detail.add_child(_row(String(field), str(fields[field])))

func _has_valid_tab() -> bool:
	return tabs.current_tab >= 0 and tabs.current_tab < _tab_keys.size()

## Detaches before freeing: queue_free() alone leaves the old rows parented for
## the rest of the frame, so the panel would briefly show two sections at once.
func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _row(key: String, value: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var key_label := Label.new()
	key_label.text = key
	key_label.custom_minimum_size = Vector2(KEY_WIDTH, 0.0)
	key_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	var value_label := Label.new()
	value_label.text = value
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Long values (the slot list) wrap instead of widening the panel.
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(key_label)
	row.add_child(value_label)
	return row
