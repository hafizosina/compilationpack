class_name EcsTakeIntentFlag
extends EcsFlag

## The brain has decided to pick something up. EcsPickupSystem takes it if it
## is still there, in reach, and there is room.

## The entity to take.
var target_id: int = EcsWorld.NO_ENTITY
