class_name EcsEditSystem
extends EcsSystem

## Applies the inspector's field edits. Knows no component type: it finds the
## component by key and sets the field when the value fits its type. Flags are
## never edited; they belong to the systems that raise them.

func label() -> StringName:
	return &"edit"

func run(world: EcsWorld, _delta: float) -> void:
	var inbox := world.get_singleton(EcsEditSingleton) as EcsEditSingleton
	if inbox == null or inbox.edits.is_empty():
		return
	for edit in inbox.edits:
		for id in edit.ids:
			if world.is_alive(id):
				_apply(world, id, edit)
	inbox.edits.clear()

func _apply(world: EcsWorld, id: int, edit: EcsEdit) -> void:
	for component in world.components_of(id):
		if component is EcsFlag or component.key() != edit.component:
			continue
		for property in component.get_property_list():
			if StringName(property["name"]) != edit.field \
					or not (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
				continue
			var value: Variant = _fit(edit.value, int(property["type"]))
			if value != null:
				component.set(edit.field, value)
			return
		return

## `value` as `type`, or null when it can't be one.
func _fit(value: Variant, type: int) -> Variant:
	if typeof(value) == type:
		return value
	match type:
		TYPE_FLOAT:
			return float(value) if value is int else null
		TYPE_INT:
			return int(value) if value is float else null
		TYPE_STRING_NAME:
			return StringName(value) if value is String else null
		TYPE_STRING:
			return String(value) if value is StringName else null
	return null
