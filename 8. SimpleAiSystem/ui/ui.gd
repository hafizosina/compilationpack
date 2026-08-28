extends CanvasLayer

## Two read-outs for the running world: population counts top-right, and a
## bottom-left inspector for whichever entity is currently selected. They are
## anchored to opposite corners rather than sharing a column, so neither can
## push or cover the other however tall the inspector grows.
##
## The panel holds no reference to an entity or to the factory. Counts and
## inspector snapshots both arrive on the EventBus already formatted, and the
## respawn button asks for a rebuild the same way — so the UI knows nothing
## about how entities are built or what any component contains.

## Width reserved for the key column so values line up.
const KEY_WIDTH := 108.0

@onready var counts_label: Label = %CountsLabel
@onready var fps_label: Label = %FpsLabel
@onready var respawn_button: Button = %RespawnButton
@onready var detail: VBoxContainer = %Detail

func _ready() -> void:
	EventBus.sim_world_spawned.connect(_on_world_spawned)
	EventBus.sim_entity_inspected.connect(_on_entity_inspected)
	respawn_button.pressed.connect(_on_respawn_pressed)
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

## Rebuilds the inspector from a snapshot. An empty dictionary means nothing is
## selected. Each component's section is rendered exactly as that component
## described itself — heading, fields and field order all come from it.
func _on_entity_inspected(details: Dictionary) -> void:
	_clear(detail)
	if details.is_empty():
		detail.add_child(_line("Click an entity to inspect it"))
		return

	detail.add_child(_line(str(details.get("name", "—"))))
	detail.add_child(HSeparator.new())
	for key in ["type", "position", "home", "from home", "slots"]:
		detail.add_child(_row(key, str(details.get(key, "—"))))

	var components: Dictionary = details.get("components", {})
	for slot in components:
		var section: Dictionary = components[slot]
		detail.add_child(HSeparator.new())
		detail.add_child(_line(str(section.get("label", slot))))
		var fields: Dictionary = section.get("fields", {})
		for field in fields:
			detail.add_child(_row(String(field), str(fields[field])))

func _on_respawn_pressed() -> void:
	EventBus.sim_respawn_requested.emit()

## Detaches before freeing: queue_free() alone leaves the old rows parented for
## the rest of the frame, so the panel would briefly show two entities at once.
func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _row(key: String, value: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var key_label := Label.new()
	key_label.text = key
	key_label.custom_minimum_size = Vector2(KEY_WIDTH, 0.0)
	var value_label := Label.new()
	value_label.text = value
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(key_label)
	row.add_child(value_label)
	return row

func _line(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label
