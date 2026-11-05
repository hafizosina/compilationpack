class_name EcsLaunchFlag
extends EcsFlag

## A launching skill is active. Added and removed by EcsSkillSystem; EcsLaunchSystem launches
## once.

## The projectile's blueprint.
var blueprint: StringName = &""
## Its damage, times the caster's EcsDamageComponent.damage.
var damage_scale: float = 1.0
## Set once it has launched.
var launched: bool = false
