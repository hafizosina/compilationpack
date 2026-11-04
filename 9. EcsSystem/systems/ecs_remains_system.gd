class_name EcsRemainsSystem
extends EcsSystem

## A death leaves what the dying entity's EcsRemainsComponent names for its cause:
## a spawn request for that blueprint where it fell, looking like it, the same size,
## holding its bag. Must run before EcsDropSystem, which would otherwise spill the bag.

func label() -> StringName:
	return &"remains"

func run(world: EcsWorld, _delta: float) -> void:
	var inbox := world.get_singleton(EcsLifecycleSingleton) as EcsLifecycleSingleton
	if inbox == null:
		return
	for id in world.query([EcsDyingFlag, EcsRemainsComponent, EcsPositionComponent]):
		var dying := world.get_component(id, EcsDyingFlag) as EcsDyingFlag
		var remains := world.get_component(id, EcsRemainsComponent) as EcsRemainsComponent
		var left: StringName = remains.leaves.get(dying.cause, &"")
		if dying.detail != &"" and remains.leaves.has(dying.detail):
			left = remains.leaves[dying.detail]
		if left == &"":
			continue
		var note := EcsSpawnRequest.new()
		note.type_id = left
		note.position = (world.get_component(id, EcsPositionComponent) as EcsPositionComponent).position
		note.overrides = _looks_of(world, id, remains.darken) if remains.darken >= 0.0 else {}

		var named := world.get_component(id, EcsNameComponent) as EcsNameComponent
		if named != null:
			note.entity_name = StringName("%s_of_%s" % [left, named.entity_name])
		var bag := world.get_component(id, EcsInventoryComponent) as EcsInventoryComponent
		if remains.keeps_bag and bag != null and not bag.items.is_empty():
			note.overrides["inventory"] = {"items": bag.items}
			bag.items = []
		inbox.spawn_requests.append(note)

## Sprite and body overrides so what it leaves looks like it.
func _looks_of(world: EcsWorld, id: int, darken: float) -> Dictionary:
	var looks: Dictionary = {}
	var sprite := world.get_component(id, EcsSpriteComponent) as EcsSpriteComponent
	if sprite != null:
		looks["sprite"] = {
			"texture": sprite.texture,
			"scale_factor": sprite.scale_factor,
			"tint": sprite.tint.darkened(darken),
		}
	var body := world.get_component(id, EcsBodyComponent) as EcsBodyComponent
	if body != null:
		looks["body"] = {"radius": body.radius}
	return looks
