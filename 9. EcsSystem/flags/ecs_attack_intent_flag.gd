class_name EcsAttackIntentFlag
extends EcsFlag

## The brain has decided to attack. EcsAttackSystem hits the target whenever the
## attack is off cooldown and the target is in reach.

## The entity to attack.
var target_id: int = EcsWorld.NO_ENTITY
