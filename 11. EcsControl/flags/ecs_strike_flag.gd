class_name EcsStrikeFlag
extends EcsFlag

## An attack skill is active. Added and removed by EcsSkillSystem; EcsStrikeSystem hits with
## it once.

## Damage per hit, times the attacker's EcsDamageComponent.damage.
var damage_scale: float = 1.0
## Degrees around the facing it hits; 360 is all around.
var arc: float = 90.0
## Seconds its swing takes.
var swing_time: float = 0.2
## Set once it has hit.
var struck: bool = false
