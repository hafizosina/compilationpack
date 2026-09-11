class_name EcsCommandSystem
extends EcsSystem

## Drains the debug-key outbox at the top of the frame. Each request toggles one
## component on one named entity — which is enough to run the whole acceptance
## test live: press the key that gives the crocodile an EcsArmorComponent and
## watch the incoming damage drop, with the attack side unrecompiled and
## unaware.

func label() -> StringName:
	return &"command"

func run(world: EcsWorld, _delta: float) -> void:
	var commands := world.get_singleton(EcsCommandsComponent) as EcsCommandsComponent
	if commands == null or commands.queued.is_empty():
		return
	for request in commands.queued:
		var template := request.get("component") as EcsComponent
		if template == null:
			continue
		var id := _find_named(world, request.get("target_name", &""))
		if id == EcsWorld.NO_ENTITY:
			push_warning("EcsCommandSystem: no entity named '%s'" % request.get("target_name"))
			continue
		var type: Script = template.get_script()
		if world.has(id, type):
			world.remove(id, type)
		else:
			# Duplicated so the queued template stays a template and can be
			# toggled back on later.
			world.add(id, template.duplicate(true))
	commands.queued.clear()

func _find_named(world: EcsWorld, wanted: StringName) -> int:
	for id in world.query([EcsNameComponent]):
		var named := world.get_component(id, EcsNameComponent) as EcsNameComponent
		if named.entity_name == wanted:
			return id
	return EcsWorld.NO_ENTITY
