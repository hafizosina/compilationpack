class_name SimBarDef
extends SimComponentDef

## Shared blueprint for the 0–100 need bars. Subclasses only pick which
## component to build; every tunable lives here.

## Full value, and the value the entity starts at.
@export var max_value: float = 100.0
@export var start_value: float = 100.0
## Units lost per second while idle.
@export var drain_per_second: float = 0.0

## PROTOTYPE display: row under the sprite to draw this bar in, or -1 for none.
@export var bar_row: int = -1
@export var bar_colour: Color = Color.WHITE

## Subclasses return the component to build.
func _make() -> SimBarComponent:
	push_error("SimBarDef._make() not implemented by %s" % get_class())
	return null

func build_into(entity: SimEntity) -> void:
	var component := _make()
	if component == null:
		return
	component.name = "%sComponent" % String(slot()).capitalize()
	component.max_value = max_value
	component.value = minf(start_value, max_value)
	component.drain_per_second = drain_per_second
	component.bar_row = bar_row
	component.bar_colour = bar_colour
	_configure(component)
	entity.add_child(component)
	entity.register_component(slot(), component)

## Hook for subclass-specific fields.
func _configure(_component: SimBarComponent) -> void:
	pass
