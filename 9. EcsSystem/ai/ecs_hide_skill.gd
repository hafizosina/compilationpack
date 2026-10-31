class_name EcsHideSkill
extends EcsSkillDef

## Lying hidden in cover. Only starts, and only holds, while in cover.

## How much of the hider it conceals, 0 to 1.
@export_range(0.0, 1.0) var stealth: float = 0.95

func make_effect() -> EcsFlag:
	var hidden := EcsHiddenFlag.new()
	hidden.stealth = stealth
	return hidden

func can_start(world: EcsWorld, id: int) -> bool:
	return EcsHunting.cover_of(world, id) > 0.0
