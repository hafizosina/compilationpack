class_name EcsProjectileSkill
extends EcsSkillDef

## A spell or shot: launches one `blueprint` along the facing.

## The projectile's blueprint; it needs EcsProjectileComponent.
@export var blueprint: StringName = &""
## Its damage, times the caster's EcsDamageComponent.damage.
@export var damage_scale: float = 1.5

func make_effect() -> EcsFlag:
	var launch := EcsLaunchFlag.new()
	launch.blueprint = blueprint
	launch.damage_scale = damage_scale
	return launch
