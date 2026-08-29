class_name SimEntitySpawnerDef
extends SimComponentDef

## Blueprint for SimEntitySpawnerComponent.

## Blueprint id to spawn — anything in the catalog.
@export var entity_id: StringName = &"berry"
## Spawns land at a random point within this radius of the spawner.
@export var radius: float = 220.0
## Seconds between spawns.
@export var cooldown: float = 1.0
## Ceiling on live entities from this spawner, so it cannot grow without bound.
@export var max_alive: int = 40

func slot() -> StringName:
	return &"spawner"

func build_into(entity: SimEntity) -> void:
	var component := SimEntitySpawnerComponent.new()
	component.name = "EntitySpawnerComponent"
	component.entity_id = entity_id
	component.radius = radius
	component.cooldown = cooldown
	component.max_alive = max_alive
	entity.add_child(component)
	entity.register_component(slot(), component)
