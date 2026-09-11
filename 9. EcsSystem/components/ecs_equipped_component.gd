class_name EcsEquippedComponent
extends EcsComponent

## The wield relationship, held as data on the wielder. Not ownership, not a
## child node — just an id, which is why an equipped weapon stays a full entity
## with its own components instead of being flattened into its holder.

## Authored link: the EcsNameComponent of the weapon to wield. A .tres cannot
## know runtime ids, so it names the thing and EcsEquipSystem resolves it.
@export var weapon_name: StringName = &""
## Where the weapon is drawn relative to its wielder.
@export var offset: Vector2 = Vector2(26.0, 4.0)

## Resolved weapon entity, or EcsWorld.NO_ENTITY while still unresolved.
var weapon_id: int = EcsWorld.NO_ENTITY

func key() -> StringName:
	return &"equipped"
