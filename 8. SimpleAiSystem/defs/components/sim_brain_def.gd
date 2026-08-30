class_name SimBrainDef
extends SimComponentDef

## Base blueprint for every brain. Subclasses pick which brain to build; this
## owns the rule that applies to all of them.
##
## **One brain per entity.** Two brains sharing one set of legs would fight over
## every move_to, so a second one is refused outright rather than allowed to
## produce behaviour nobody can debug. The check lives here so every brain kind
## inherits it, including ones that do not exist yet.

func slot() -> StringName:
	return &"brain"

## Subclasses return the brain to build.
func _make() -> SimBrainComponent:
	push_error("SimBrainDef._make() not implemented by %s" % _script_name(self))
	return null

func build_into(entity: SimEntity) -> void:
	var existing := entity.get_component(slot())
	if existing != null:
		push_error("'%s' already has a brain (%s); an entity may hold only one, so %s was not built"
			% [entity.name, _script_name(existing), _script_name(self)])
		return
	var component := _make()
	if component == null:
		return
	component.name = "BrainComponent"
	_configure(component)
	entity.add_child(component)
	entity.register_component(slot(), component)

## Hook for subclass-specific fields.
func _configure(_brain: SimBrainComponent) -> void:
	pass

## get_class() reports the engine type (Node2D, Resource), which says nothing
## about which brain this is. The script filename is what a reader needs.
static func _script_name(object: Object) -> String:
	var script: Script = object.get_script()
	if script == null:
		return object.get_class()
	return script.resource_path.get_file()
