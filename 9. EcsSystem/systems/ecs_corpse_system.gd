class_name EcsCorpseSystem
extends EcsSystem

## A death by health leaves a corpse: a spawn request for the `corpse`
## blueprint where it fell, looking like it, the same size, holding its bag.
## Must run before EcsDropSystem, which would otherwise spill the bag.

## Corpses are drawn this much darker than the creature.
const DARKEN: float = 0.55

func label() -> StringName:
	return &"corpse"

func run(world: EcsWorld, _delta: float) -> void:
	var inbox := world.get_singleton(EcsLifecycleSingleton) as EcsLifecycleSingleton
	if inbox == null:
		return
	for id in world.query([EcsDyingFlag, EcsHealthComponent, EcsPositionComponent]):
		if (world.get_component(id, EcsHealthComponent) as EcsHealthComponent).value > 0.0:
			continue
		var note := EcsSpawnRequest.new()
		note.type_id = &"corpse"
		note.position = (world.get_component(id, EcsPositionComponent) as EcsPositionComponent).position
		note.overrides = _looks_of(world, id)

		var named := world.get_component(id, EcsNameComponent) as EcsNameComponent
		if named != null:
			note.entity_name = StringName("corpse_of_%s" % named.entity_name)
		var bag := world.get_component(id, EcsInventoryComponent) as EcsInventoryComponent
		if bag != null and not bag.items.is_empty():
			note.overrides["inventory"] = {"items": bag.items}
			bag.items = []
		inbox.spawn_requests.append(note)

## Sprite and body overrides so the corpse looks like what died.
func _looks_of(world: EcsWorld, id: int) -> Dictionary:
	var looks: Dictionary = {}
	var sprite := world.get_component(id, EcsSpriteComponent) as EcsSpriteComponent
	if sprite != null:
		looks["sprite"] = {
			"texture": sprite.texture,
			"scale_factor": sprite.scale_factor,
			"tint": sprite.tint.darkened(DARKEN),
		}
	var body := world.get_component(id, EcsBodyComponent) as EcsBodyComponent
	if body != null:
		looks["body"] = {"radius": body.radius}
	return looks
