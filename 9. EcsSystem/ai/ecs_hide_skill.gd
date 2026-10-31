class_name EcsHideSkill
extends EcsSkillDef

## Lying hidden in cover of a kind it can use. Only starts, and only holds, while in it.

## How much of the hider it conceals, 0 to 1.
@export_range(0.0, 1.0) var stealth: float = 0.9
## The cover kinds it can hide in.
@export var kinds: Array[StringName] = [&"bush"]

func make_effect() -> EcsFlag:
	var hidden := EcsHiddenFlag.new()
	hidden.stealth = stealth
	return hidden

func can_start(world: EcsWorld, id: int) -> bool:
	return EcsHunting.cover_of(world, id) > 0.0
