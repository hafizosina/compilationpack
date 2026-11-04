class_name EcsFieldEditor
extends RefCounted

## Builds one input control for a field from its property entry (type, hint,
## hint_string), and refreshes it from a new value. Holds no data: the caller
## says what a change does.

## A control for a field of `property`'s type showing `value`, which calls
## `on_change(new_value)`; null for a type it can't edit.
static func build(property: Dictionary, value: Variant, on_change: Callable) -> Control:
	var type := int(property["type"])
	match type:
		TYPE_FLOAT, TYPE_INT:
			if int(property["hint"]) == PROPERTY_HINT_ENUM:
				var options := OptionButton.new()
				options.focus_mode = Control.FOCUS_NONE
				for label in String(property["hint_string"]).split(","):
					options.add_item(label.get_slice(":", 0))
				options.select(int(value))
				options.item_selected.connect(func(index: int) -> void: on_change.call(index))
				return options
			var spin := _spin(float(value), type == TYPE_INT)
			spin.value_changed.connect(func(number: float) -> void:
				on_change.call(int(number) if type == TYPE_INT else number))
			return spin
		TYPE_BOOL:
			var check := CheckBox.new()
			check.focus_mode = Control.FOCUS_NONE
			check.button_pressed = bool(value)
			check.toggled.connect(func(on: bool) -> void: on_change.call(on))
			return check
		TYPE_STRING, TYPE_STRING_NAME:
			var line := LineEdit.new()
			line.text = str(value)
			line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.theme_type_variation = &"DockField"
			line.text_submitted.connect(func(_text: String) -> void: line.release_focus())
			line.text_changed.connect(func(text: String) -> void:
				on_change.call(StringName(text) if type == TYPE_STRING_NAME else text))
			return line
		TYPE_VECTOR2:
			var pair := HBoxContainer.new()
			var x := _spin((value as Vector2).x, false)
			var y := _spin((value as Vector2).y, false)
			x.value_changed.connect(func(n: float) -> void: on_change.call(Vector2(n, y.value)))
			y.value_changed.connect(func(n: float) -> void: on_change.call(Vector2(x.value, n)))
			x.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			y.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pair.add_child(x)
			pair.add_child(y)
			return pair
		TYPE_COLOR:
			var color := ColorPickerButton.new()
			color.focus_mode = Control.FOCUS_NONE
			color.color = value
			color.custom_minimum_size = Vector2(80, 0)
			color.color_changed.connect(func(c: Color) -> void: on_change.call(c))
			return color
	return null

## Shows `value` on a control from `build()` without firing its change, unless
## the user is typing in it.
static func refresh(control: Control, value: Variant) -> void:
	if control is OptionButton:
		if (control as OptionButton).selected != int(value):
			(control as OptionButton).select(int(value))
	elif control is SpinBox:
		var spin := control as SpinBox
		if not spin.get_line_edit().has_focus() and not is_equal_approx(spin.value, float(value)):
			# Blocked rather than set_value_no_signal, which leaves the shown text stale.
			spin.set_block_signals(true)
			spin.value = float(value)
			spin.set_block_signals(false)
	elif control is CheckBox:
		(control as CheckBox).set_pressed_no_signal(bool(value))
	elif control is LineEdit:
		var line := control as LineEdit
		if not line.has_focus() and line.text != str(value):
			line.text = str(value)
	elif control is ColorPickerButton:
		var color := control as ColorPickerButton
		if not color.get_popup().visible:
			color.color = value
	elif control is HBoxContainer and value is Vector2 and control.get_child_count() == 2:
		refresh(control.get_child(0) as Control, (value as Vector2).x)
		refresh(control.get_child(1) as Control, (value as Vector2).y)

static func _spin(value: float, whole: bool) -> SpinBox:
	var spin := SpinBox.new()
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.min_value = -100000.0
	spin.max_value = 100000.0
	spin.step = 1.0 if whole else 0.01
	spin.value = value
	spin.custom_minimum_size = Vector2(72, 0)
	spin.get_line_edit().theme_type_variation = &"DockField"
	return spin
