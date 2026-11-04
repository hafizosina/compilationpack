extends PanelContainer

## Module 9's entity detail dock, one scrolling page: the first selected entity's
## bars, summary and flags, then a foldable card per component with its on/off
## switch and its fields edited in place. Edits and removals go to every selected
## entity over EventBus; never touches the world.

const KEY_WIDTH := 110.0
const VALUE_WIDTH := 64.0
## Tones a component's bars may name; others get the plain bar.
const TONES := [&"health", &"fullness", &"energy", &"hydration", &"danger"]

@onready var _name: Label = %NameLabel
@onready var _subtitle: Label = %Subtitle
@onready var _focus: Button = %FocusButton
@onready var _remove: Button = %RemoveButton
@onready var _scroll: ScrollContainer = %Scroll
@onready var _bars: VBoxContainer = %Bars
@onready var _summary: VBoxContainer = %Summary
@onready var _flags: HFlowContainer = %Flags
@onready var _cards: VBoxContainer = %Cards
@onready var _empty: Label = %EmptyHint

## Ids of every selected entity; edits and removals go to all of them.
var _ids: Array = []
## Component key -> true when its card is open. Kept across selections.
var _open: Dictionary = {}

var _bar_rows: Dictionary = {}  # label -> [ProgressBar, Label]
var _summary_rows: Dictionary = {}  # label -> Label
var _flag_texts: Array = []
## Card key -> {head, check, body, sig, lines: {label: Label}, editors: {field: Control}}
var _card_views: Dictionary = {}
var _card_order: Array = []

func _ready() -> void:
	EventBus.ecs_entity_inspected.connect(_on_entity_inspected)
	_focus.pressed.connect(func() -> void:
		if not _ids.is_empty():
			EventBus.ecs_camera_focus_requested.emit(_ids[0]))
	_remove.pressed.connect(func() -> void:
		if not _ids.is_empty():
			EventBus.ecs_entity_remove_requested.emit(_ids.duplicate()))
	_on_entity_inspected({})

func _on_entity_inspected(details: Dictionary) -> void:
	var nothing := details.is_empty()
	_empty.visible = nothing
	_scroll.visible = not nothing
	_focus.disabled = nothing
	_remove.disabled = nothing
	if nothing:
		_ids = []
		_name.text = "Nothing selected"
		_subtitle.text = ""
		_remove.text = "Remove"
		return

	_ids = details.get("ids", [])
	_name.text = str(details.get("name", "—"))
	_subtitle.text = "%s   ·   #%d" % [details.get("type", "—"), int(details.get("id", 0))]
	if _ids.size() > 1:
		_subtitle.text += "   ·   +%d more selected, edits apply to all" % (_ids.size() - 1)
	_remove.text = "Remove %d" % _ids.size() if _ids.size() > 1 else "Remove"
	_show_bars(details.get("bars", []))
	_show_summary(details.get("summary", {}))
	_show_flags(details.get("flags", []))
	_show_cards(details.get("cards", []))

# --- bars, summary, flags ----------------------------------------------------

func _show_bars(bars: Array) -> void:
	var labels: Array = bars.map(func(bar: Dictionary) -> String: return bar["label"])
	if labels != _bar_rows.keys():
		_clear(_bars)
		_bar_rows = {}
		for bar: Dictionary in bars:
			var row := _row(_bars, bar["label"])
			var meter := ProgressBar.new()
			meter.show_percentage = false
			meter.custom_minimum_size = Vector2(0, 12)
			meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var tone: StringName = bar.get("tone", &"")
			meter.theme_type_variation = StringName("DockBar" + String(tone).capitalize()) \
				if TONES.has(tone) else &"DockBar"
			var value := Label.new()
			value.theme_type_variation = &"DockLabel"
			value.custom_minimum_size = Vector2(VALUE_WIDTH, 0)
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			row.add_child(meter)
			row.add_child(value)
			_bar_rows[bar["label"]] = [meter, value]
	for bar: Dictionary in bars:
		var meter: ProgressBar = _bar_rows[bar["label"]][0]
		var top := maxf(float(bar["max"]), 0.0001)
		meter.max_value = top
		meter.value = float(bar["value"])
		var shown: Label = _bar_rows[bar["label"]][1]
		shown.text = "%d%%" % roundi(float(bar["value"]) / top * 100.0) if is_equal_approx(top, 1.0) \
			else "%d/%d" % [roundi(float(bar["value"])), roundi(top)]

func _show_summary(summary: Dictionary) -> void:
	if summary.keys() != _summary_rows.keys():
		_clear(_summary)
		_summary_rows = {}
		for key in summary:
			_summary_rows[key] = _value_label(_row(_summary, str(key)))
	for key in summary:
		(_summary_rows[key] as Label).text = str(summary[key])

func _show_flags(flags: Array) -> void:
	if flags == _flag_texts:
		return
	_flag_texts = flags.duplicate()
	_clear(_flags)
	_flags.visible = not flags.is_empty()
	for text in flags:
		var chip := Label.new()
		chip.theme_type_variation = &"DockChip"
		chip.text = str(text)
		_flags.add_child(chip)

# --- cards -------------------------------------------------------------------

## Cards are rebuilt only when the set of components changes; a card's body only
## when its own lines or fields change; otherwise values refresh in place.
func _show_cards(cards: Array) -> void:
	var order: Array = cards.map(func(card: Dictionary) -> StringName: return card["key"])
	if order != _card_order:
		_clear(_cards)
		_card_views = {}
		_card_order = order
		for card: Dictionary in cards:
			_card_views[card["key"]] = _make_card(card)
	for card: Dictionary in cards:
		_fill_card(_card_views[card["key"]], card)

func _make_card(card: Dictionary) -> Dictionary:
	var key: StringName = card["key"]
	var box := VBoxContainer.new()
	box.theme_type_variation = &"SimVBox"
	var header := HBoxContainer.new()
	header.theme_type_variation = &"SimHBox"
	var check := CheckBox.new()
	check.focus_mode = Control.FOCUS_NONE
	check.theme_type_variation = &"DockCheck"
	check.tooltip_text = "On or off; off counts as not having it"
	check.toggled.connect(func(on: bool) -> void:
		if not _ids.is_empty():
			EventBus.ecs_entity_edit_requested.emit(_ids.duplicate(), key, &"enabled", on))
	var head := Button.new()
	head.focus_mode = Control.FOCUS_NONE
	head.theme_type_variation = &"DockCardHead"
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(check)
	header.add_child(head)
	var body := VBoxContainer.new()
	body.theme_type_variation = &"SimVBox"
	box.add_child(header)
	box.add_child(body)
	_cards.add_child(box)
	var view := {"head": head, "check": check, "body": body, "sig": [], "lines": {}, "editors": {},
		"label": card["label"]}
	head.pressed.connect(func() -> void:
		_open[key] = not _open.get(key, false)
		_fold(view, key))
	return view

func _fill_card(view: Dictionary, card: Dictionary) -> void:
	var key: StringName = card["key"]
	var enabled: bool = card["enabled"]
	(view["check"] as CheckBox).set_pressed_no_signal(enabled)
	view["label"] = card["label"] + ("" if enabled else "  (off)")
	var lines: Dictionary = card["lines"]
	var fields: Dictionary = card["fields"]
	var sig := [lines.keys(), fields.keys()]
	if sig != view["sig"]:
		view["sig"] = sig
		var body: VBoxContainer = view["body"]
		_clear(body)
		view["lines"] = {}
		view["editors"] = {}
		for line in lines:
			view["lines"][line] = _value_label(_row(body, str(line)))
		for field in fields:
			var editor := EcsFieldEditor.build(fields[field], fields[field]["value"],
				_requester(key, StringName(field)))
			_style_editor(editor)
			_row(body, str(field)).add_child(editor)
			view["editors"][field] = editor
	for line in lines:
		(view["lines"][line] as Label).text = str(lines[line])
	for field in fields:
		EcsFieldEditor.refresh(view["editors"][field], fields[field]["value"])
	_fold(view, key)

func _fold(view: Dictionary, key: StringName) -> void:
	var open: bool = _open.get(key, false)
	(view["body"] as Control).visible = open
	(view["head"] as Button).text = ("▾  " if open else "▸  ") + str(view["label"])

func _requester(component: StringName, field: StringName) -> Callable:
	return func(value: Variant) -> void:
		if not _ids.is_empty():
			EventBus.ecs_entity_edit_requested.emit(_ids.duplicate(), component, field, value)

# --- rows ---------------------------------------------------------------------

## A row under `parent` with `key` in the key column; the caller adds the value.
func _row(parent: Control, key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.theme_type_variation = &"SimHBox"
	var label := Label.new()
	label.theme_type_variation = &"DockHint"
	label.text = key
	label.custom_minimum_size = Vector2(KEY_WIDTH, 0.0)
	label.clip_text = true
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	row.add_child(label)
	parent.add_child(row)
	return row

func _value_label(row: HBoxContainer) -> Label:
	var value := Label.new()
	value.theme_type_variation = &"DockLabel"
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(value)
	return value

func _style_editor(editor: Control) -> void:
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if editor is LineEdit:
		editor.theme_type_variation = &"DockField"
	elif editor is CheckBox:
		editor.theme_type_variation = &"DockCheck"
	elif editor is Button:
		editor.theme_type_variation = &"DockButton"

## Detaches before freeing so old rows don't show for a frame.
func _clear(parent: Control) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
