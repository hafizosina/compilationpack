class_name EcsSkillDef
extends Resource

## One skill: its timing, what being active means, and when it may start.
## EcsSkillSystem runs every skill the same way; a subclass says only its effect
## and its requirement.

## The id an EcsCastIntentFlag names.
@export var id: StringName = &""
## Seconds before it can be cast again, counted from when it ends.
@export var cooldown: float = 0.0
## Seconds it lasts. 0 is held: it lasts while asked for and `can_start` holds.
@export var duration: float = 0.0

## The flag that is this skill being active. Added and removed only by EcsSkillSystem.
func make_effect() -> EcsFlag:
	return null

## May `id` start it now, or keep holding it?
func can_start(_world: EcsWorld, _id: int) -> bool:
	return true
